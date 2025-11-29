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

# Running the test
1) Run `ruby dsda-index.rb` to build the index of dsda demos.
2) Once index is complete, run `ruby dsda-sync.rb` to download all demos.
3) Run `ruby dsda-reg-test.rb` to run the entire regression test.
4) When the test completes, `results.csv` and `failures.csv` (if there are failures) will be created in `regression-test/data-export/`.

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
