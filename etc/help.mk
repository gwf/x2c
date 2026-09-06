define PRINT_HELP_PYSCRIPT
import re
import sys
import textwrap

entries = []
target_width = 0
for line in sys.stdin:
    group = re.match(r'^##@ (.+)$$', line)
    if group:
        entries.append(("group", group.group(1), ""))
        continue
    target = re.match(r'^([0-9A-Za-z_-]+):.*?## (.*)$$', line)
    if target:
        name, description = target.groups()
        entries.append(("target", name, description))
        target_width = max(target_width, len(name))

description_column = 2 + target_width + 2
description_width = 80 - description_column
output = []
for kind, name, description in entries:
    if kind == "group":
        if output:
            output.append("")
        output.append(name)
        continue
    prefix = "  " + name.ljust(target_width) + "  "
    wrapped = textwrap.wrap(
        description,
        width=description_width,
        break_long_words=False,
        break_on_hyphens=False,
    ) or [""]
    output.append(prefix + wrapped[0])
    output.extend(" " * description_column + line for line in wrapped[1:])
print("\n".join(output))
endef
export PRINT_HELP_PYSCRIPT
