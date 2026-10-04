# After — the capture this phase is measured against

Captured from `433108e3` with the same harness, the same fixtures and the same frozen animations as
`../baseline`, which was captured from the pre-phase commit `ad3eecff`.

| | baseline (`ad3eecff`) | after (`433108e3`) |
|---|---|---|
| surfaces | 68 | 68 |
| captures | 544 | 544 |
| controls | 5,088 | 5,678 |
| **unnamed controls** | **1,578** | **0** |
| horizontal overflow | 0 | 0 |
| wrong text direction | 0 | 0 |
| page / console errors | 0 | 0 |
| screenshots | 272 | 272 |

`parity-gate.txt` is the gate's own output over the two directories:

```
compared 544 captures
  lost 0   moved-with-reason 8   added 598   newly-named 1466   regressions 0
```

Of the 544 captures, **0 lost a control**: 300 are unchanged in control count and 244 gained one or more.

Screenshots are named `<surface>-<locale>-<width>.png` at 390 and 1280; the inventory covers 390, 768,
1024 and 1280. To compare one surface, open the same filename in both directories.

Reproduce:

```
bash docs/ui-modernization/harness/shoot.sh docs/ui-modernization/after
node docs/ui-modernization/harness/parity.mjs \
  docs/ui-modernization/baseline docs/ui-modernization/after
```
