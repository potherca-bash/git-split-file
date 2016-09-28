---
permalink: /
---

# Git Split File

Split a file in a git repository without losing the git history.

## Introduction

Usually when a file in a git repository is split into several different files,
the history gets lost.

Often this is not desirable.

`git-split-file` allows for split files to retain their history.

Splitting a file still needs to be done manually but this script will take care
of branching/moving/renaming/committing/merging/etc. the split files.

See the usage section for details on how to do this.

## Installation

Clone or download this repository or the single file `git-split-file.sh`

## Usage

In short all that needs to be done is manually split a file and call `git-split-file`

There are, however, some details to take into account.

### Manually splitting the file

You have a file in a git repository that you would like to split into several
files.

First create a directory the split files can be placed in. This directory does
not have to reside in the git repository the file to split is in.

Next split that file into several different files. The more of the order and
whitespace is left intact, the more of the history will also be left intact.

Under some circumstances it is desirable to have a truncated version of the file
that has been split, under other circumstances the file that has been split can
be removed completely. Both scenarios are supported.

In the scenario where the file is to be deleted, just leave the contents of that
file as-is. `git-split-file` will simply remove the file for you.

In the scenario where a change version of the file is to remain in the repository,
add a version of the file as it should eventually be in the directory that also holds the other split files.
`git-split-file` will commit the changes for you. It is possible to tell the
script to either leave the file in the same location or move it to the same
location as the other split files.


### Calling the script

As the final result can live outside of the repository, the script can easily be
run on a clone to verify everything works out as desired.

In order to function, the script needs to know a few things:

- The source file that is to be split (the source file)
- The directory where the split files are located (the source directory)
- The location where the split files should be placed in the repository (the target path)
- Whether to delete, keep or move the source file. (the split strategy)

Currently moving the source file to another location than the target path is not
supported.

## How it works

As a picture might communicate matter more clearly than mere words, consider the
following:

            A---bN--cN      split branch N
           /         \
          A---B---C   \     split branch one
         /         \   \
        A-------D---E---eN     source branch
       /                  \
    --A--------------------F--  root branch

- `A` is the last known commit on the root branch.
- A separate branch is made to function as the "source" to and from other branches are split off.
- For each file in the source directory a copy of the source file is created (using `git mv $SOURCE $TARGET`) leading to commit `B` (and `bN`).
- The content of the copied file is updated (using `cat $CONTENT > $TARGET` and `git add/commit $TARGET`) leading to commit `C` (and `cN`).
- The content of the source file is updated leading to commit `D`.
- Each split branch is then merged into the source branch, resolving any conflicts that occur, leading to commit `E` (and `eN`).
- When all branches have been merged, everything is merged back to the root branch. Commit `F` now has all of the changes.

## Origin / Motivation

When working in low-quality code-bases that have grown organically over time, it
is not uncommon to encounter files that span several (tens of) thousands of lines.

For various reasons it is desirable to split such files into smaller files.

Instead of doing this by hand, it made more sense to automate parts of the process.

<!--

## Contributing

Please see [CONTRIBUTING] for details.

## Change Log

Please see [CHANGELOG] for details.

## Credits

logo / images / ?

-->

## License

This project has been licensed under GPL-3.0+ License.