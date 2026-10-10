#pragma once

macro Decorator $fixture.imported(Function $target) {
  @(Code.body $target)
}
