#include "x2c.x"

// A free name reads the definitions its body was written next to. The
// caller's binding of the same name is not part of that chain.
$(defun read-free () free-name)
$(defun caller () (let ((free-name 1)) (read-free)))
$(caller)

int value;
