/*  record.x -- one field table for the notes wire and storage record */
#pragma once
#include "json.x"

typedef struct Note Note;

meta static List note_fields(void) =>
  %((id String optional) (title String required) (body String optional)
    (tags Array optional) (created long optional) (updated long optional));

meta static List note_declarations(void) {
  Array fields = [];
  foreach (List row in note_fields()) {
    List type = row[1] == <long> ? %(long) : $(row[1].str());
    List name = $(row[0].str());
    fields.push(%(declare $type (bindings (bind $name ()))));
  }
  return fields.list_free();
}

macro Unit $note.record(Name $name) {
  struct $name { @note_declarations() };
}
$note.record(Note);

meta static List note_map(void) {
  Array entries = [];
  foreach (List row in note_fields()) {
    String key = row[0].str();
    List name = x2c_ident(row[0].str());
    entries.push($!{ result[$(key)] = note.$(name); });
  }
  List statements = entries.list_free();
  return $!{ @statements };
}

Map Note.to_map(Note note) {
  Map result = {};
  $note_map();
  return result;
}

meta static List note_read(void) {
  Array statements = [];
  foreach (List row in note_fields()) {
    String key = row[0].str(), type = row[1].str();
    List name = x2c_ident(key);
    if (type == "String") {
      String reason = %"$key must be text";
      statements.push($!{
        if (values[$(key)] is not void && values[$(key)] is not <string>)
          _note_invalid($(reason));
        note.$(name) = values[$(key)] is void ? NULL : values[$(key)];
      });
      if (row[2] == <required>) statements.push($!{
        if (!note.$(name)) raise %(note-error (reason "title is required"));
      });
    }
    else if (type == "Array") statements.push($!{
      if (values[$(key)] is not void && values[$(key)] is not <array>)
        raise %(note-error (reason "tags must be an array"));
      note.$(name) = values[$(key)] is void ? [] : values[$(key)];
      foreach (Var tag in note.$(name))
        if (tag is not <string> || !tag.string())
          raise %(note-error (reason "each tag must be nonempty text"));
    });
    else statements.push($!{
      if (values[$(key)] is not void && !values[$(key)].is_integer())
        raise %(note-error (reason "timestamps must be integers"));
      note.$(name) = values[$(key)] is void ? 0 : values[$(key)];
    });
  }
  List body = statements.list_free();
  return $!{ @body };
}

Note Note.from_map(Map values) {
  Note note = {0};
  $note_read();
  return note;
}

meta List note_columns(void) {
  Array names = [];
  foreach (List row in note_fields()) names.push(row[0].str());
  String columns = names.join(", ");
  return $!( $(columns) );
}

static void _note_invalid(String reason) {
  raise %(note-error (reason $reason));
}
