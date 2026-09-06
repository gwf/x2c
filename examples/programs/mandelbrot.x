/*  mandelbrot.x -- render a deep zoom on native threads */

#include <math.h>
#include <stdio.h>
#include "typed-array.x"

static const int nworkers = 10, width = 960, height = 540, maxits = 5000;

typedef struct Job {
  int worker;
  ArrayDbl pixels;
} *Job;

static Var render(const void *input, size_t ignored) {
  const Job job = (Job) input;
  for (int y = job.worker; y < height; y += nworkers) {
    double unit_y = 2.0 * y / (height - 1) - 1.0;
    double cy = 0.131825904205330 + 5e-8 * height / width * unit_y;
    for (int x = 0; x < width; x++) {
      double unit_x = 2.0 * x / (width - 1) - 1.0;
      double cx = -0.743643887037151 + 5e-8 * unit_x;
      double zx = 0.0, zy = 0.0;
      int iter = 0;
      while (zx * zx + zy * zy <= 4.0 && iter < maxits) {
        double next = zx * zx - zy * zy + cx;
        zy = 2.0 * zx * zy + cy;
        zx = next;
        iter++;
      }
      double smooth = -1.0;
      if (iter < maxits) {
        double magnitude = 0.5 * log(zx * zx + zy * zy);
        smooth = iter + 1.0 - log(magnitude) / log(2.0);
      }
      job.pixels[y * width + x] = smooth;
    }
  }
  return void;
}

static ArrayChar _rgb(ArrayDbl pixels) {
  ArrayChar rgb = %[];
  rgb.append(NULL, pixels.len() * 3);
  int at = 0;
  foreach (double value, pixels) {
    double t = value < 0.0 ? 0.0 : fmod(value * 0.015, 1.0);
    double u = 1.0 - t;
    rgb[at++] = (char) (9.0 * u * t * t * t * 255.0);
    rgb[at++] = (char) (15.0 * u * u * t * t * 255.0);
    rgb[at++] = (char) (8.5 * u * u * u * t * 255.0);
  }
  return rgb;
}

static void write_image(String path, ArrayChar rgb) {
  File output = File.open(path, "wb");
  defer output.close();
  output.puts(%"P6\n$width $height\n255");
  output.write_all(rgb.bytes, rgb.len());
}

int main(int argc, char **argv) {
  Scope.retain();
  String path = argc > 1 ? argv[1] : "mandelbrot.ppm";
  ArrayDbl pixels = %[];
  pixels.append(NULL, width * height);
  Array threads = %[];
  for (int worker = 0; worker < nworkers; worker++) {
    struct Job job = { worker, pixels };
    threads.push(Thread.start(render, &job, sizeof(job)));
  }
  for (int worker = 0; worker < nworkers; worker++) {
    Thread thread = threads[worker];
    thread.join();
    thread.free();
  }
  write_image(path, _rgb(pixels));
  puts(%"wrote $path");
  Scope.release();
  return 0;
}
