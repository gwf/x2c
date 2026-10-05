// lint: allow contains-in ST-5: wrong rule ID
int wrong_rule(Map map, String key) => map.contains(key);

// lint: allow contains-in ST-11:
int empty_reason(Map map, String key) => map.contains(key);

// lint: allow plain-string EX-3: wrong code for this finding
int wrong_code(Map map, String key) => map.contains(key);

// lint: allow unknown-rule ST-11: unknown lint code
int unknown_code(Map map, String key) => map.contains(key);

String fake_comment = "// lint: allow contains-in ST-11: string content";
int after_string(Map map, String key) => map.contains(key);

/* lint: allow contains-in ST-11: block comment content */
int after_block(Map map, String key) => map.contains(key);

// lint: allow contains-in ST-11: blank line intervenes

int after_blank(Map map, String key) => map.contains(key);

int label = 1; // lint: allow contains-in ST-11: trailing comment
int after_trailing(Map map, String key) => map.contains(key);
