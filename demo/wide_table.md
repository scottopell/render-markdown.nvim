# Wide Table Horizontal Scroll Demo

This file demonstrates horizontal scroll behavior with very wide, wide tables.

## Instructions

1. Open this file with render-markdown enabled
2. Position cursor on a table row
3. Use `zl` / `zh` to scroll horizontally (or `zL` / `zH` for half-screen)
4. Observe rendering behavior as leftcol changes

## Narrow Table (reference - should always render correctly)

| A | B | C |
|---|---|---|
| 1 | 2 | 3 |

## Wide Table (scroll test)

| Column_A | Column_B | Column_C | Column_D | Column_E | Column_F | Column_G | Column_H | Column_I | Column_J | Column_K | Column_L |
|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|----------|
| A1_data  | B1_data  | C1_data  | D1_data  | E1_data  | F1_data  | G1_data  | H1_data  | I1_data  | J1_data  | K1_data  | L1_data  |
| A2_data  | B2_data  | C2_data  | D2_data  | E2_data  | F2_data  | G2_data  | H2_data  | I2_data  | J2_data  | K2_data  | L2_data  |
| A3_data  | B3_data  | C3_data  | D3_data  | E3_data  | F3_data  | G3_data  | H3_data  | I3_data  | J3_data  | K3_data  | L3_data  |

## Wide Table with Mixed Alignment

| Left_Aligned | Center_Aligned | Right_Aligned | Default_Col | Left_Again | Center_Again | Right_Again | Default_Again |
|:-------------|:--------------:|--------------:|-------------|:-----------|:------------:|------------:|---------------|
| LLLLLLLLLLLL | CCCCCCCCCCCCCC | RRRRRRRRRRRRRR | DDDDDDDDDDDD | LLLLLLLLLL | CCCCCCCCCCCC | RRRRRRRRRRRR | DDDDDDDDDDDD |
| short        | short          | short         | short       | short      | short        | short       | short         |

## Varying Cell Widths

| Short | Medium_Length | VeryLongColumnHeader | X |
|-------|---------------|----------------------|---|
| a     | bbbbb         | cccccccccccccccccccc | d |
| ee    | fff           | g                    | h |

## Minimal Table

| A | B |
|---|---|
| 1 | 2 |

## Table with Single Long Cell

| Normal | This_cell_has_very_long_content_that_extends_far_to_the_right | End |
|--------|---------------------------------------------------------------|-----|
| x      | y                                                             | z   |

## Indented Table (in list)

- List item with table:

  | Indented_A | Indented_B | Indented_C | Indented_D |
  |------------|------------|------------|------------|
  | val1       | val2       | val3       | val4       |

## Table with Only Left Alignment

| Left1 | Left2 | Left3 | Left4 | Left5 |
|:------|:------|:------|:------|:------|
| AAAAA | BBBBB | CCCCC | DDDDD | EEEEE |

## Table with Only Right Alignment

| Right1 | Right2 | Right3 | Right4 | Right5 |
|-------:|-------:|-------:|-------:|-------:|
| AAAAA  | BBBBB  | CCCCC  | DDDDD  | EEEEE  |

## Table with Only Center Alignment

| Center1 | Center2 | Center3 | Center4 | Center5 |
|:-------:|:-------:|:-------:|:-------:|:-------:|
| AAAAA   | BBBBB   | CCCCC   | DDDDD   | EEEEE   |

## Expected Behavior

When scrolling horizontally:
- Table borders should remain aligned with cell content
- No duplicate pipe characters should appear
- Delimiter row (---) should render correctly
- Padding should stay consistent
- Alignment indicators (━) should appear in correct positions

## Debug Info

Check leftcol with: `:echo winsaveview().leftcol`
