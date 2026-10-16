/*  definitions.x -- macro definitions, quotations and holes */

/* macro definitions

   Reading a definition takes its result kind, name, signature holes, and
   body. Its signature is visible before the body is read, so the body can
   invoke the macro it defines. */

/* One definition while it is read. `nested` marks a definition inside a
   template, which stays syntax until the template's expansion binds it.
   `locals` holds the template's own declarations, newest first under
   `<order>`, and `captures` the outer names a local macro's body reads. */
static typedef struct Definition {
  Compiler c, Token start;
  Atom name, Symbol kind;
  List target, parameters, template, fresh, captures, pattern, rebuild, type;
  List origin, String file, Map locals, Array using;
  int anonymous, local, nested, quotation, leaf, storage;
} Definition;

module {
  "definitions/reading.x",
  "definitions/templates.x",
  "definitions/quotations.x",
  "definitions/slots.x",
}
