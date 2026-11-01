// Notes serves the same SQLite-backed notes API as the x2c application.
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"sync"
	"syscall"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

const schema = "CREATE TABLE IF NOT EXISTS note (" +
	"id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, " +
	"body TEXT NOT NULL, tags TEXT NOT NULL, " +
	"created INTEGER NOT NULL, updated INTEGER NOT NULL)"

const selectAll = "SELECT id, title, body, tags, created, updated FROM note ORDER BY id"
const selectOne = "SELECT id, title, body, tags, created, updated FROM note WHERE id = ?"
const insertNote = "INSERT INTO note (title, body, tags, created, updated) " +
	"VALUES (?, ?, ?, ?, ?) RETURNING id"
const updateNote = "UPDATE note SET title = ?, body = ?, tags = ?, updated = ? " +
	"WHERE id = ? RETURNING id, title, body, tags, created, updated"

// Field order matches the x2c JSON writer's lexical object-key order.
type note struct {
	Body    string   `json:"body"`
	Created int64    `json:"created"`
	ID      string   `json:"id"`
	Tags    []string `json:"tags"`
	Title   string   `json:"title"`
	Updated int64    `json:"updated"`
}

type app struct {
	db *sql.DB
	mu sync.Mutex
}

type options struct {
	host, store, public string
	port, workers       int
}

func main() { os.Exit(run()) }

func run() int {
	o, err := arguments(os.Args[1:])
	if errors.Is(err, flag.ErrHelp) {
		return 0
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "notes:", err)
		return 2
	}
	if err := serve(o); err != nil {
		fmt.Fprintln(os.Stderr, "notes:", err)
		return 1
	}
	return 0
}

func arguments(args []string) (options, error) {
	o := options{}
	flags := flag.NewFlagSet("notes", flag.ContinueOnError)
	flags.SetOutput(os.Stdout)
	flags.Usage = func() {
		fmt.Fprintln(flags.Output(), "Usage: notes [options]")
		flags.VisitAll(func(f *flag.Flag) {
			fmt.Fprintf(flags.Output(), "  --%s: %s (default %s)\n", f.Name, f.Usage, f.DefValue)
		})
	}
	flags.StringVar(&o.host, "host", "127.0.0.1", "Listen on this address")
	flags.IntVar(&o.port, "port", 8080, "TCP port; 0 selects one")
	flags.IntVar(&o.workers, "workers", 8, "Concurrent-client setting; net/http schedules goroutines")
	flags.StringVar(&o.store, "store", "notes.db", "SQLite database file")
	flags.StringVar(&o.public, "public", "examples/apps/notes/public", "Browser assets directory")
	if err := flags.Parse(args); err != nil {
		return o, err
	}
	if flags.NArg() != 0 || o.port < 0 || o.port > 65535 || o.workers < 1 || o.workers > 1024 {
		return o, errors.New("port must be 0..65535 and workers must be 1..1024; no positional arguments")
	}
	return o, nil
}

func serve(o options) error {
	absolute, err := filepath.Abs(o.store)
	if err != nil {
		return err
	}
	dsn := (&url.URL{Scheme: "file", Path: absolute}).String() +
		"?_journal_mode=DELETE&_synchronous=FULL&_busy_timeout=0"
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		return err
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	if _, err = db.Exec(schema); err != nil {
		return err
	}
	var version, journal string
	var synchronous, busy int
	if err = db.QueryRow("SELECT sqlite_version()").Scan(&version); err != nil {
		return err
	}
	if err = db.QueryRow("PRAGMA journal_mode").Scan(&journal); err != nil {
		return err
	}
	if err = db.QueryRow("PRAGMA synchronous").Scan(&synchronous); err != nil {
		return err
	}
	if err = db.QueryRow("PRAGMA busy_timeout").Scan(&busy); err != nil {
		return err
	}
	log.Printf("sqlite version=%s journal=%s synchronous=%d busy_timeout=%d connections=1",
		version, journal, synchronous, busy)
	a := &app{db: db}
	mux := http.NewServeMux()
	mux.HandleFunc("/api/notes", a.notes)
	mux.HandleFunc("/api/notes/{id}", a.one)
	mux.HandleFunc("/api/stats", a.stats)
	mux.Handle("/", http.FileServer(http.Dir(o.public)))
	server := &http.Server{Handler: accessLog(mux), ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout: 5 * time.Second, IdleTimeout: 5 * time.Second, MaxHeaderBytes: 64 << 10}
	listener, err := net.Listen("tcp", net.JoinHostPort(o.host, strconv.Itoa(o.port)))
	if err != nil {
		return err
	}
	defer listener.Close()
	fmt.Printf("Notes: http://%s/\n", listener.Addr())
	stopping, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	finished := make(chan error, 1)
	go func() { finished <- server.Serve(listener) }()
	select {
	case err := <-finished:
		return err
	case <-stopping.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdown); err != nil {
			server.Close()
			return err
		}
		return nil
	}
}

func (a *app) notes(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.list(w, r)
	case http.MethodPost:
		a.create(w, r)
	default:
		fail(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func (a *app) one(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.get(w, r)
	case http.MethodPut:
		a.update(w, r)
	case http.MethodDelete:
		a.delete(w, r)
	default:
		fail(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func (a *app) list(w http.ResponseWriter, r *http.Request) {
	tag, query := r.URL.Query().Get("tag"), r.URL.Query().Get("q")
	var pattern *regexp.Regexp
	var err error
	if query != "" {
		pattern, err = regexp.Compile(query)
		if err != nil {
			fail(w, 400, "invalid search pattern")
			return
		}
	}
	notes := make([]note, 0)
	err = func() error {
		a.mu.Lock()
		defer a.mu.Unlock()
		statement, err := a.db.Prepare(selectAll)
		if err != nil {
			return err
		}
		defer statement.Close()
		rows, err := statement.Query()
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			n, err := readNote(rows)
			if err != nil {
				return err
			}
			if tag != "" && !hasTag(n.Tags, tag) {
				continue
			}
			if pattern != nil && !pattern.MatchString(n.Title) && !pattern.MatchString(n.Body) {
				continue
			}
			notes = append(notes, n)
		}
		return rows.Err()
	}()
	if internal(w, err) {
		return
	}
	writeJSON(w, 200, notes)
}

func (a *app) get(w http.ResponseWriter, r *http.Request) {
	var n note
	err := func() error {
		a.mu.Lock()
		defer a.mu.Unlock()
		statement, err := a.db.Prepare(selectOne)
		if err != nil {
			return err
		}
		defer statement.Close()
		rows, err := statement.Query(r.PathValue("id"))
		if err != nil {
			return err
		}
		defer rows.Close()
		if !rows.Next() {
			if err := rows.Err(); err != nil {
				return err
			}
			return sql.ErrNoRows
		}
		n, err = readNote(rows)
		return err
	}()
	if errors.Is(err, sql.ErrNoRows) {
		fail(w, 404, "no such note")
		return
	}
	if !internal(w, err) {
		writeJSON(w, 200, n)
	}
}

func (a *app) create(w http.ResponseWriter, r *http.Request) {
	n, ok := noteInput(w, r)
	if !ok {
		return
	}
	n.Created = time.Now().Unix()
	n.Updated = n.Created
	tags, _ := json.Marshal(n.Tags)
	err := func() error {
		a.mu.Lock()
		defer a.mu.Unlock()
		statement, err := a.db.Prepare(insertNote)
		if err != nil {
			return err
		}
		defer statement.Close()
		rows, err := statement.Query(n.Title, n.Body, string(tags), n.Created, n.Updated)
		if err != nil {
			return err
		}
		defer rows.Close()
		if !rows.Next() {
			if err := rows.Err(); err != nil {
				return err
			}
			return sql.ErrNoRows
		}
		var id int64
		if err := rows.Scan(&id); err != nil {
			return err
		}
		n.ID = strconv.FormatInt(id, 10)
		for rows.Next() {
		}
		return rows.Err()
	}()
	if !internal(w, err) {
		writeJSON(w, 201, n)
	}
}

func (a *app) update(w http.ResponseWriter, r *http.Request) {
	n, ok := noteInput(w, r)
	if !ok {
		return
	}
	tags, _ := json.Marshal(n.Tags)
	err := func() error {
		a.mu.Lock()
		defer a.mu.Unlock()
		statement, err := a.db.Prepare(updateNote)
		if err != nil {
			return err
		}
		defer statement.Close()
		rows, err := statement.Query(n.Title, n.Body, string(tags), time.Now().Unix(), r.PathValue("id"))
		if err != nil {
			return err
		}
		defer rows.Close()
		if !rows.Next() {
			if err := rows.Err(); err != nil {
				return err
			}
			return sql.ErrNoRows
		}
		n, err = readNote(rows)
		if err != nil {
			return err
		}
		for rows.Next() {
		}
		return rows.Err()
	}()
	if errors.Is(err, sql.ErrNoRows) {
		fail(w, 404, "no such note")
		return
	}
	if !internal(w, err) {
		writeJSON(w, 200, n)
	}
}

func (a *app) delete(w http.ResponseWriter, r *http.Request) {
	var changed int64
	err := func() error {
		a.mu.Lock()
		defer a.mu.Unlock()
		statement, err := a.db.Prepare("DELETE FROM note WHERE id = ?")
		if err != nil {
			return err
		}
		defer statement.Close()
		result, err := statement.Exec(r.PathValue("id"))
		if err != nil {
			return err
		}
		changed, err = result.RowsAffected()
		return err
	}()
	if internal(w, err) {
		return
	}
	if changed == 0 {
		fail(w, 404, "no such note")
		return
	}
	writeJSON(w, 200, map[string]bool{"deleted": true})
}

func (a *app) stats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		fail(w, 405, "method not allowed")
		return
	}
	tags := make(map[string]int64)
	var count, bytes int64
	err := func() error {
		a.mu.Lock()
		defer a.mu.Unlock()
		statement, err := a.db.Prepare("SELECT title, body, tags FROM note")
		if err != nil {
			return err
		}
		defer statement.Close()
		rows, err := statement.Query()
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var title, body, encoded string
			if err := rows.Scan(&title, &body, &encoded); err != nil {
				return err
			}
			var values []string
			if err := json.Unmarshal([]byte(encoded), &values); err != nil {
				return err
			}
			count++
			bytes += int64(len(title) + len(body))
			for _, tag := range values {
				tags[tag]++
			}
		}
		return rows.Err()
	}()
	if !internal(w, err) {
		writeJSON(w, 200, map[string]any{"notes": count, "bytes": bytes, "tags": tags})
	}
}

func noteInput(w http.ResponseWriter, r *http.Request) (note, bool) {
	if len(r.TransferEncoding) != 0 {
		fail(w, 411, "request requires Content-Length")
		return note{}, false
	}
	if r.ContentLength > 1<<20 {
		fail(w, 413, "body too large")
		return note{}, false
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, (1<<20)+1))
	if err != nil {
		fail(w, 400, "cannot read request body")
		return note{}, false
	}
	if len(body) > 1<<20 {
		fail(w, 413, "body too large")
		return note{}, false
	}
	var value any
	if err := json.Unmarshal(body, &value); err != nil {
		fail(w, 400, "malformed JSON")
		return note{}, false
	}
	fields, ok := value.(map[string]any)
	if !ok {
		fail(w, 422, "expected a note object")
		return note{}, false
	}
	title, ok := fields["title"].(string)
	if !ok || title == "" {
		fail(w, 422, "title is required")
		return note{}, false
	}
	bodyText := ""
	if value, present := fields["body"]; present {
		bodyText, ok = value.(string)
		if !ok {
			fail(w, 422, "body must be text")
			return note{}, false
		}
	}
	tags := make([]string, 0)
	if value, present := fields["tags"]; present {
		values, ok := value.([]any)
		if !ok {
			fail(w, 422, "tags must be an array")
			return note{}, false
		}
		for _, value := range values {
			tag, ok := value.(string)
			if !ok || tag == "" {
				fail(w, 422, "each tag must be nonempty text")
				return note{}, false
			}
			tags = append(tags, tag)
		}
	}
	return note{Title: title, Body: bodyText, Tags: tags}, true
}

func readNote(rows *sql.Rows) (note, error) {
	var n note
	var id int64
	var tags string
	if err := rows.Scan(&id, &n.Title, &n.Body, &tags, &n.Created, &n.Updated); err != nil {
		return n, err
	}
	n.ID = strconv.FormatInt(id, 10)
	return n, json.Unmarshal([]byte(tags), &n.Tags)
}

func hasTag(tags []string, target string) bool {
	for _, tag := range tags {
		if tag == target {
			return true
		}
	}
	return false
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	body, err := json.Marshal(value)
	if err != nil {
		fail(w, 500, "internal server error")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	w.WriteHeader(status)
	w.Write(body)
}

func fail(w http.ResponseWriter, status int, reason string) {
	writeJSON(w, status, map[string]string{"error": reason})
}

func internal(w http.ResponseWriter, err error) bool {
	if err == nil {
		return false
	}
	log.Printf("error/http error=%q", err)
	fail(w, 500, "internal server error")
	return true
}

type accessWriter struct {
	http.ResponseWriter
	status int
}

func (w *accessWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *accessWriter) Write(body []byte) (int, error) {
	if w.status == 0 {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(body)
}

func accessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		logged := &accessWriter{ResponseWriter: w}
		next.ServeHTTP(logged, r)
		if logged.status == 0 {
			logged.status = http.StatusOK
		}
		log.Printf("info/http status=%d path=%q", logged.status, r.URL.Path)
	})
}
