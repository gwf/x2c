// Fixed-body Go comparison for the notes loopback benchmark.
package main

import (
    "fmt"
    "net/http"
    "os"
    "time"
)

func main() {
    if len(os.Args) != 2 { os.Exit(2) }
    body := []byte(`{"id":"1","title":"benchmark","body":"hello","tags":[],"created":0,"updated":0}`)
    mux := http.NewServeMux()
    mux.HandleFunc("/api/notes/1", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != "GET" || r.URL.Path != "/api/notes/1" {
            http.NotFound(w, r)
            return
        }
        w.Header().Set("Content-Type", "application/json")
        w.Write(body)
    })
    server := &http.Server{Addr: "127.0.0.1:" + os.Args[1], Handler: mux,
        ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 5 * time.Second}
    if err := server.ListenAndServe(); err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
}
