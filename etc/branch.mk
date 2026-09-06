###############################################################################
# --- Sanitize BRANCH variable for binary suffixes and X2C selection ---
# Get the raw branch name from git. Ensure it's evaluated only once.
_BRANCH_RAW_GIT := $(shell git symbolic-ref --short HEAD 2>/dev/null)
# Process the raw git branch name.
ifeq ($(_BRANCH_RAW_GIT),)
    # Not in a git repo, git command failed, or other issue returning empty.
    _BRANCH_INTERMEDIATE := non_git_or_unknown
else ifeq ($(_BRANCH_RAW_GIT),HEAD)
    # Detached HEAD state.
    _BRANCH_INTERMEDIATE := detached_head
else
    # Substitute '/' with '_' for a valid suffix.
    _BRANCH_INTERMEDIATE := $(subst /,_,${_BRANCH_RAW_GIT})
endif
# Final BRANCH variable to be used.
# $(strip ...) removes leading/trailing whitespace.
BRANCH := $(strip $(_BRANCH_INTERMEDIATE))
# Fallback if BRANCH is somehow still empty after stripping.
ifeq ($(BRANCH),)
    BRANCH := unknown_branch
endif
# --- End Sanitize BRANCH variable ---
