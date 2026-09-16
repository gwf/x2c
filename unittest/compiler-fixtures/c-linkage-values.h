#ifdef __cplusplus
extern "C" {
#endif

typedef struct Point { int x, y; } Point;

static inline int Point_sum(Point point) { return point.x + point.y; }

#ifdef __cplusplus
}
#endif
