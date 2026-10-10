#pragma once

macro Decorator $project.imported(
  Function $function
) {
  @(Code.body $function)
}
