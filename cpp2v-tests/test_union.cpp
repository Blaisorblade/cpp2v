/*
 * Copyright (C) BedRock Systems Inc. 2019-20
 *
 * SPDX-License-Identifier:MIT-0
 */

struct U {
    int x;
    int y;
};
union U_init {
    int x;
    int y {1};
};

enum E {
    a , b
};
