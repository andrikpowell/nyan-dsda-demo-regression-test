# Nyan / DSDA-Doom Demo Regression Test
How to run the test:

# Files needed
1) Add IWADs into `regression-test/support/wads` (`DOOM2.WAD`, `DOOM.WAD`, `HERETIC.WAD`, `HEXEN.WAD`, `PLUTONIA.wad`, `TNT.wad`). [see `readme.txt` in directory for more info].
2) Download both Junkfood 4 and Eviternity II wads and extract them into `regression-test/support/wads/EX` (they are too large for github).
3) (Optional) Add Commerical WADs into `regression-test/support/wads/EX/CM` (see `readme.txt` in directory for more info).
4) (Optional) Add Master Levels into `regression-test/support/wads/EX/CM/ML`.

>Note: Specific Commerical and Master Levels will be skipped (marked as pass) if they are not present.

# EXE Setup
1) Build new exe in `build`.
2) Build old exe (regression test exe) in `build/build-old/`.
3) Install ruby (latest version).
4) Install parallel with `gem install parallel`.
5) Setup paths / variables in `regression-test/support/dsda-test-prefs.rb` (you may need to adjust the amount of cores to use).
6) Make sure that all overflow warnings are set to false (`0`), but overflow emulations are set to true (`1`) in `nyan-doom.cfg` / `dsda-doom.cfg` (for both exes):
```
# Overrun settings
overrun_spechit_warn             0
overrun_spechit_emulate          1
overrun_reject_warn              0
overrun_reject_emulate           1
overrun_intercept_warn           0
overrun_intercept_emulate        1
overrun_playeringame_warn        0
overrun_playeringame_emulate     1
overrun_donut_warn               0
overrun_donut_emulate            1
overrun_missedbackside_warn      0
overrun_missedbackside_emulate   1
```

# Running the test
1) Enter the `regression-test` directory
2) Run `ruby dsda-index.rb` to build the index of dsda demos.
3) Once index is complete, run `ruby dsda-sync.rb` to download all demos.
4) Run `ruby dsda-reg-test.rb` to run the entire regression test.
5) When the test completes, `results.csv` and `failures.csv` (if there are failures) will be created in `regression-test/data-export/`.

# Fixing Failures / Editing Overrides
1) Once the test is completed, if there are failures they will be created in `regression-test/data-export/`.
2) The test uses `Overrides.csv` to get specific demos to run correctly (or to force a skip)
3) Open both `Failures.csv` and `Overrides.csv`
4) `Failures.csv` will include a cmdline and demo folder path for easy testing and troubleshooting.
6) First, see if you can use the `IwadOverride`, `FileOverride`, or `ExtraArgs` fields to get the demo to sync
   - `IwadOverride` - rare, but sometimes the demo may be for the wrong iwad. (example: `doom2.wad`)
   - `FileOverride` - relative to the current wad folder; Each file should be separated via `,`; For external, commerical, or Master Levels, use the aliases `EX/, CM/, ML/`; The alias `demo_dir/` corresponds to the current demo folder; note that the order of the wads is the load order and will override the current `-file` arguments (example: `EX/nerve.wad, cool.wad, fix/cool.deh, demo_dir/patch.deh`).
   - `ExtraArgs` - includes any extra arguments you may need to get the demo to sync. Note that all the arguments should be surrounded by double quotes (example: `"-complevel 5 -nodeh"`)
7) If you can't get the demo to sync, than you may need to `Skip` it. There are many reasons for skipping demos, but by default the demo is still ran for regression checking, but is "skipped" in regards to marking against the test. There are cases where a demo can cause a freeze, crash, or simply takes too long to run... This takes the `Reason` column into account, which is where we specify the reason for the skip. These reasons will not run the demo at all and truly skip it: `crash`, `freeze`, `unpredicatable`, `duplicate`, `ignore`, `wrong wad`, `wrong iwad`, `too long`.
8) Once you fill out the fields make sure to also fill out the `Action` column with `Override` or `Skip`
9) Now copy the "fixed" row from `Failures.csv` and paste it into `Overrides.csv`. All CSVs follow the same column structure, so they are easy to transfer over.
10) Now in order to see if you've fixed those demos, you can re-run `dsda-reg-test.rb` with `--failed-only` and it'll only re-test the failed demos... If specific demos then pass, they will be updated in `Overrides.csv`.
11) `Failures.csv` will be deleted if all the failures have been resovled.

# Re-indexing / Re-syncing
- If you want to grab any new demos, following the current dsda index you have, you can re-run `dsda-sync.rb` and it will only grab new demos.
- However, if you need to grab demos from new wads, you will have to re-run `dsda-index.rb` to index the new wad first.

# Options for sync and test
- `dsda-sync.rb`
  - `--force` Force overwrite extracted content
  - `--skip-wads` Don't download/extract wad zips
  - `--skip-demos` Don't download/extract demo zips
  - `--retry-failed` Retry only failed demos
- `dsda-reg-test.rb`
  - Running the test without any options wil run the entire test.
  - `<iwad>` run all the demos for a single IWAD
  - `<iwad>/<wad>` run all the demos for a single WAD
  - `<iwad>/<wad>/<demo>` run all the demos inside a single demo folder
  - `--failed-only` run only the demos that failed during the last test (see `regression-test/data-export/failures.csv`).
