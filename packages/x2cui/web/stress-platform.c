#include <emscripten.h>

/* Suspend the browser demo without discarding its workload or controls. */
EM_ASYNC_JS(int, stress_wait_visible, (), {
    if (!document.hidden) return 0;
    await new Promise(resolve => {
        function visible() {
            if (document.hidden) return;
            document.removeEventListener('visibilitychange', visible);
            resolve();
        }
        document.addEventListener('visibilitychange', visible);
    });
    return 1;
});
