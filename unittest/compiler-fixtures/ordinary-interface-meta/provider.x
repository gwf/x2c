#pragma once
meta static int _ordinary_meta_step(int value) => value + 1;
meta int ordinary_meta_value(int value) => _ordinary_meta_step(value);
