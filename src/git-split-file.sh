#!/usr/bin/env bash

#===============================================================================
# @TODO: Use named parameters instead of relying on parameter order
# ------------------------------------------------------------------------------
# @TODO: Add parameter to set author
# ------------------------------------------------------------------------------
# @TODO: Add silent mode (-s / --silent) to suppress all output
# ------------------------------------------------------------------------------
# @TODO: Add yes mode (-y / --yes) to run without questions
# ------------------------------------------------------------------------------
# @FIXME: The cleanup gives errors if cleanup is run before/without the split being run
# ------------------------------------------------------------------------------
# @FIXME: Add "aggressive" mode that creates a commit on the source branch (?before/after? merge)
#         of the source file with all of the lines from the split file removed.
# - Using grep?
# - Programmatically creating a git patch?
# - Doing a "reverse" patch? (http://stackoverflow.com/questions/16059771/reverse-apply-a-commit-to-working-copy)
# - Creating a reverse diff? (http://stackoverflow.com/a/3902431/153049)
# - Use patch created with GNU diff and use patch --reverse? (http://www.gnu.org/software/diffutils/manual/html_node/Reversed-Patches.html)
# So many options.
#
# grep -Fvxf <remove> <all-lines>
#===============================================================================

#/==============================================================================
#/                               GIT SPLIT FILE
#/------------------------------------------------------------------------------
## Usage: git.split.sh <source-file> <source-path> <target-path> <split-strategy>
##
## Where:
##       - <source-file> is the file in a git repository you would like to be split
##       - <source-path> is the directory that holds the result of how you would like
##         things to be after the file has been split.
##       - <target-path> is the directory where the split files should be committed to
##       - <split-strategy> is the strategy that should be applied to the source-file
##         Can be one of DELETE | MOVE
##
#/ Usually when you want to split a file into several files under git, you would
#/ loose the git history of this file. Often this is not desirable. The goal of
#/ this script is to enable splitting one file under Git revision control into
#/ multiple files whilst keeping the file's git history intact.
#/
#/ For this script to work, you need to first create a folder that contains the
#/ end result you want. This means you need to manually split the content of the
#/ file you want to keep into separate files. The more of the order and
#/ whitespace you leave intact, the more of the history will also be left intact.
#
#/ Once you have everything to your liking, you point this script to the file you
#/ want to split, the folder that holds the desired end result and the location
#/ where the result should be placed.
#/
#/ This script will then branch of from the branch the designated git repo is on
#/ for each file to split into. It will then split the given root file, commit
#/ the split result and merge it back to the branch it was originally on.
#/ ------------------------------------------------------------------------------
#/ The following ExitCodes are used:
#/
#/  0 : Everything OK
#/ 64 : Undefined Error
#/
#/ 65 : Not enough parameters given
#/ 66 : The given root file does not exist
#/ 67 : The given root file is not part of a git repository
#/ 68 : Given split directory path does not exist
#/ 69 : Given split directory path is not a directory
#/ 70 : Given split strategy is not supported
#/
# Please note that g_iExitCode needs to be set *before* error() is called,
# otherwise the ExitCode will default to 64.
#==============================================================================


# ==============================================================================
#                               CONFIG VARS
# ------------------------------------------------------------------------------
# DEBUG_LEVEL 0 = No Debugging
# DEBUG_LEVEL 1 = Show Debug messages
# DEBUG_LEVEL 2 = " and show Application Calls
# DEBUG_LEVEL 3 = " and show called command
# DEBUG_LEVEL 4 = " and show all other commands (=set +x)
# DEBUG_LEVEL 5 = Show All Commands, without Debug Messages or Application Calls
# ==============================================================================


# ==============================================================================
#                                APPLICATION VARS
# ------------------------------------------------------------------------------
# For all options see http://www.tldp.org/LDP/abs/html/options.html
set -o nounset      # Exit script on use of an undefined variable, same as "set -u"
set -o errexit      # Exit script when a command exits with non-zero status, same as "set -e"
set -o pipefail     # Makes pipeline return the exit status of the last command in the pipe that failed

declare g_bInsideGitRepo=false
declare g_bShowHelp=false
declare -a g_aErrorMessages
declare -i g_iExitCode=0
declare -i g_iErrorCount=0

readonly g_sBranchPrefix='split-file'
readonly g_sColorDim=$(tput dim)
readonly g_sColorRestore=$(tput sgr0)

: readonly "${GIT_AUTHOR:=Potherca-Bot <potherca+bot@gmail.com>}"
# ==============================================================================


# ==============================================================================
#                           UTILITY FUNCTIONS
# ==============================================================================
# ==============================================================================
# Store given message in the ErrorMessage array
# ------------------------------------------------------------------------------
error() {
    if [[ ! -z "${2:-}" ]];then
        g_iExitCode=${2}
    elif [[ "${g_iExitCode}" -eq 0 ]];then
        g_iExitCode=64
    fi

    g_iErrorCount=$((g_iErrorCount+1))

    g_aErrorMessages[${g_iErrorCount}]="${1}\n"

    return ${g_iExitCode};
}
# ==============================================================================

# ==============================================================================
printMessage() {
# ------------------------------------------------------------------------------
    echo -e "# ${*}" >&1
}
# ==============================================================================

# ==============================================================================
# Output all given Messages to STDERR
# ------------------------------------------------------------------------------
printErrorMessages() {
    echo -e "\nErrors occurred:\n\n ${*}" >&2
}
# ==============================================================================

# ==============================================================================
# ------------------------------------------------------------------------------
printStatus() {
    echo "-----> $*"
}
# ==============================================================================

# ==============================================================================
# ------------------------------------------------------------------------------
printTopic() {
    echo
    echo "=====> $*"
}
# ==============================================================================

# ==============================================================================
# Usage:
# Displays all lines in main script that start with '##'
# ------------------------------------------------------------------------------
shortUsage() {
    grep '^##' <"$0" | cut -c4-
}
# ==============================================================================


# ==============================================================================
# Usage:
# Displays all lines in main script that start with '#/'
# ------------------------------------------------------------------------------
fullUsage() {
    grep '^#/' <"$0" | cut -c4-

    shortUsage
}
# ==============================================================================


# ==============================================================================


# ==============================================================================
# Sets script variables based on input, when valid.
#
# The following variables will be set:
#
# - g_bInsideGitRepo
# - g_sRootBranch
# - g_bShowHelp
# - g_sSourceBranch
# - g_sSourceFileName
# - g_sSourceFilePath
# - g_sSplitDirectory
# - g_sStrategy
# - g_sTargetDirectory
#
# ------------------------------------------------------------------------------
handleParams() {
    local iDebugLevel sParam sRootFile sSplitDirectory

    iDebugLevel=0

    for sParam in "$@";do
        if [[ "${sParam}" = "--help" ]];then
            g_bShowHelp=true
        elif [[ "${sParam}" = "--verbose" || "${sParam}" = "-v" ]];then
            iDebugLevel=1
        elif [[ "${sParam}" = "-vv" ]];then
            iDebugLevel=2
        elif [[ "${sParam}" = "-vvv" ]];then
            iDebugLevel=2
        fi
    done

    readonly DEBUG_LEVEL="${iDebugLevel}"

    if [[ "${g_bShowHelp}" = false && "$#" -lt 4 ]];then
        g_iExitCode=65
        error 'This script expects four command-line arguments'
    elif [[ "${g_bShowHelp}" = false ]];then

        sRootFile=$(readlink -f "${1}")
        sSplitDirectory=$(readlink -f "${2}")
        readonly g_sTargetDirectory=$(readlink -f "${3}")
        readonly  g_sStrategy="${4}"

        if [[ ! -f "${sRootFile}" ]];then
            g_iExitCode=66
            error "The given root file '${1}' does not exist"
        else
            readonly g_sSourceFilePath="${sRootFile}"
            readonly g_sSourceFileName=$(basename "${g_sSourceFilePath}")

            # shellcheck disable=SC2086
            if [[ "$(git status ${g_sSourceFilePath} > /dev/null 2>&1 || echo '1')" ]];then
                g_iExitCode=67
                error "The given split file '${g_sSourceFilePath}' is not part of a git repository"
            else
                g_bInsideGitRepo=true
                readonly g_sRootBranch=$(getCurrentBranch)
                readonly g_sSourceBranch="${g_sBranchPrefix}_${g_sSourceFileName}"
            fi
        fi

        if [[ ! -e "${sSplitDirectory}" ]];then
            g_iExitCode=68
            error "The given split directory '${2}' does not exist"
        elif [[ ! -d "${sSplitDirectory}" ]];then
            g_iExitCode=69
            error "The given split directory '${2}' is not a directory"
        else
            readonly g_sSplitDirectory="${sSplitDirectory}"
        fi

        if [[ "${g_sStrategy}" != 'DELETE' && "${g_sStrategy}" != 'MOVE' ]];then
            g_iExitCode=71
            error "The given split strategy '${g_sStrategy}' is not one of supported DELETE | MOVE"
        fi
    fi

    return ${g_iExitCode}
}
# ==============================================================================

# ##############################################################################
#                              UTILITY FUNCTIONS
# ##############################################################################
printDebug() {
    local aCaller

    if [[ "${DEBUG_LEVEL}" -gt 0 && "${DEBUG_LEVEL}" -lt 5 ]];then
        aCaller=($(caller))
        printf "${g_sColorDim}[DEBUG] (line %04d): %s${g_sColorRestore}\n" "${aCaller[0]}"  "$*" >&2
    fi
}

getCurrentBranch() {
    git rev-parse --abbrev-ref HEAD
}

commit() {
    printStatus 'Creating commit'
    git commit --author="${GIT_AUTHOR}" --message="${1}."
}

git_merge() {

    local -r sBranch="${1?One parameter required: <branch> [merge-strategy]}"
    local -r sMergeStrategy="${2:-}"

    if [[ "${sMergeStrategy}" == '' ]];then
        git merge --no-ff --no-edit "${sBranch}"
    else
        git merge --no-ff --no-edit -X "${sMergeStrategy}" "${sBranch}"
    fi

    git commit --amend --author="${GIT_AUTHOR}" --no-edit
}

createBranch() {
    local sBranchName sStartBranch

    sBranchName="${1}"
    sStartBranch="${2}"

    #git checkout -b "${sBranchName}" "${sStartBranch}"
    git branch "${sBranchName}" "${sStartBranch}"
}

createSourceBranch() {
    printTopic 'Creating separate branch to merge split files back into'
    createBranch "${g_sSourceBranch}" "${g_sRootBranch}"
}

createBranchName() {
    local sFile

    sFile=$(basename "${1}")

    echo "${g_sSourceBranch}_${sFile}"
}

createSplitBranch() {
    printStatus "Creating separate branch to split file '${1}'"
    createBranch "$(createBranchName "${1}")" "${g_sSourceBranch}"
}

checkoutBranch() {
    printStatus "Switching to ${2} branch"
    git checkout "${1}"
}

checkoutSplitBranch() {
    local sBranchName sFile

    sFile="${1}"

    sBranchName=$(createBranchName "${sFile}")

    checkoutBranch "${sBranchName}" 'split'
}

checkoutRootBranch() {
    checkoutBranch "${g_sRootBranch}" 'root'
}

checkoutSourceBranch() {
    checkoutBranch "${g_sSourceBranch}" 'source'
}

mergeSplitBranch() {
    local sBranchName sFile
    local -i iResult=0
    sFile="${1}"

    sBranchName=$(createBranchName "${sFile}")

    printTopic "Merging branch '${sBranchName}' back into '$(getCurrentBranch)'"

    # shellcheck disable=SC2086
    if [[ -n "$(git show-ref refs/heads/${sBranchName})" ]];then
        printStatus "Branch '${sBranchName}' exists"

        (
            git_merge "${sBranchName}" 'theirs' && printStatus 'No merge conflict'
        ) || (
            printStatus 'Merge conflict occurred. Attempting to resolve.'
            git add -- "${g_sSourceFilePath}" \
                && commit "Merging split file '${g_sSourceFileName}'"
        ) || (
            printStatus 'Merge conflict remains. Attempting to resolve more aggressively.'
            git add $(git status | grep -o -E 'added by us: .*' | cut -d ':' -f 2) \
                && commit "Merging split file '${g_sSourceFileName}'"
        )
    else
        printStatus "Branch does not exist. No need to merge"
    fi
}

renameFile() {
    local sFile

    sFile="${1}"

    if [[ ! -f "${g_sSourceFilePath}" ]];then
        printStatus "File '${g_sSourceFilePath}' does not exist. Checking out from '${g_sRootBranch}'"
        git checkout "${g_sRootBranch}" -- "${g_sSourceFilePath}"
    fi

    if [[ ! -d "${g_sTargetDirectory}" ]];then
        printStatus "Target directory '${g_sTargetDirectory}' does not exist"
        printStatus "Creating target directory '${g_sTargetDirectory}'"
        mkdir -p "${g_sTargetDirectory}"
    fi

    if [[ "${sFile}" = "${g_sSourceFileName}" ]];then
        printStatus "File is root file '${g_sSourceFileName}', no need to rename"
    else
        printStatus "Creating separate file for '${sFile}'"
        git mv "${g_sSourceFilePath}" "${g_sTargetDirectory}/${sFile}"
        commit "Adds separate file for '${sFile}'"
    fi
}

commitFileContent() {
    local sFile sMessage sTargetFile

    sFile="${1}"

    if [[ "${sFile}" = "${g_sSourceFileName}" ]];then
        printStatus "Writing content to source file '${g_sSourceFileName}'"
        sMessage="Removes content that has been split of from '${sFile}'"
        sTargetFile="${g_sSourceFilePath}"
    else
        printStatus "Writing content to target file '${g_sTargetDirectory}/${sFile}'"
        sMessage="Changes content in separated file '${sFile}'"
        sTargetFile="${g_sTargetDirectory}/${sFile}"
    fi

    cat "${g_sSplitDirectory}/${sFile}" > "${sTargetFile}"
    git add "${sTargetFile}"
    commit "${sMessage}"
}

createSubBranches() {
    local sFile

    printTopic 'Creating sub-branches'
    for sFile in "${g_sSplitDirectory}/"*;do
        # if [[ "${sFile}" = "${g_sSourceFileName}" && "${g_sStrategy}" != "MOVE" ]];then
        #     printStatus "Skipping branch for source file '${g_sSourceFileName}'"
        # else
            createSplitBranch "${sFile}"
        # fi
    done
}

splitFiles() {
    local sFile sFileName

    for sFile in "${g_sSplitDirectory}/"*;do
        sFileName=$(basename "${sFile}")
        if [[ "${sFileName}" = "${g_sSourceFileName}" ]];then
            printTopic "Skipping source file '${g_sSourceFileName}'"
        else
            printTopic "Running split processing for file '${sFile}'"

            printDebug "sFile = ${sFile}"
            printDebug "sFileName = ${sFileName}"

            checkoutSplitBranch "${sFile}"
            renameFile "${sFileName}"
            commitFileContent "${sFileName}"
        fi
    done
}

mergeSplitBranches() {
    local sFile

    printTopic 'Merging all the split branches into the source branch'

    checkoutSourceBranch

    for sFile in "${g_sSplitDirectory}/"*;do
        if [[ "$(basename ${sFile})" = "$(basename ${g_sSourceFileName})" ]];then
            printTopic "Skipping source file '${g_sSourceFileName}'"
        else
            printTopic "Running merge processing for file '${sFile}'"
            mergeSplitBranch "${sFile}"
        fi
    done

    printTopic 'All file-split branches have been merged into the main split branch'
}

runCleanup() {
    local sBranchName sFile

    if [[ "${g_sSourceBranch:-}" && "${g_sSplitDirectory:-}" ]];then
        read -n1 -p 'Cleanup all the things? (y/n) ' sContinue
        echo ""

        if [[ "${sContinue}" = 'y' ]];then
            printStatus 'Removing all the split branches that were created'

            if [[ ${g_bInsideGitRepo} = true && "${g_sRootBranch}" != "$(getCurrentBranch)" ]];then
                git merge --abort
                checkoutRootBranch
            fi

            git branch -D "${g_sSourceBranch}"

            for sFile in "${g_sSplitDirectory}/"*;do
                sBranchName=$(createBranchName "${sFile}")

                # shellcheck disable=SC2086
                if [[ -n "$(git show-ref refs/heads/${sBranchName})" ]];then
                    # Branch exists
                    git branch -D "${sBranchName}"
                fi
            done
            sBranchName=$(createBranchName "${g_sSourceFileName}")

            # shellcheck disable=SC2086
            if [[ -n "$(git show-ref refs/heads/${sBranchName})" ]];then
                # Branch exists
                git branch -D "${sBranchName}"
            fi

        else
            printStatus 'Leaving everything as-is.'
        fi
    fi

    printMessage '================================================================================'
}

printHeader() {
    printMessage "               running $(basename $0)"
    printMessage "       for source file ${g_sSourceFilePath}"
    printMessage " with source directory ${g_sSplitDirectory}"
    printMessage "   to target directory ${g_sTargetDirectory}"
    printMessage "  using split strategy ${g_sStrategy}"

    printDebug "g_sRootBranch      = ${g_sRootBranch}"
    printDebug "g_sSourceBranch    = ${g_sSourceBranch}"
    printDebug "g_sSourceFilePath  = ${g_sSourceFilePath}"
    printDebug "g_sSourceFileName  = ${g_sSourceFileName}"
    printDebug "g_sSplitDirectory  = ${g_sSplitDirectory}"
    printDebug "g_sTargetDirectory = ${g_sTargetDirectory}"
    printDebug "g_sStrategy        = ${g_sStrategy}"
}

run() {

    printHeader

    if [[ "${DEBUG_LEVEL}" -gt 0 ]];then
        printStatus "Debugging on - Debug Level : ${DEBUG_LEVEL}"
    fi

    read -n1 -p 'Does this look correct? (y/n) ' sContinue
    echo ""

    if [[ "${sContinue}" = 'y' ]];then
        createSourceBranch

        # Process all non-source files
        createSubBranches
        splitFiles
        mergeSplitBranches

        # Process the source file
        printTopic "Running split process for source file '${g_sSourceFileName}'"
        checkoutSourceBranch

        if [[ ${g_sStrategy} = 'MOVE' ]];then
            commitFileContent "${g_sSourceFileName}"
            mergeSplitBranch "${g_sSourceFileName}"
        elif [[ ${g_sStrategy} = 'DELETE' ]];then
            printStatus 'Nothing to do for DELETE as file has already been renamed.'
            # git rm "${g_sSourceFilePath}"
            # commit "Removes '${g_sSourceFilePath}' file that has been split."
        else
            error "Unsupported merge strategy '${g_sStrategy}'" 70
        fi

        printTopic "Merging source branch '${g_sSourceBranch}' into the root branch '${g_sRootBranch}'"
        checkoutRootBranch

        git_merge "${g_sSourceBranch}"
    else
        printMessage 'Aborting.'
    fi
}

finish() {
    if [[ ! "${bFinished:-}" ]];then

        readonly bFinished=true

        if [[ ! ${g_iExitCode} -eq 0 ]];then
            printErrorMessages "${g_aErrorMessages[*]}"

            if [[ ${g_iExitCode} -eq 65 ]];then
                shortUsage
                echo 'Call --help for more details'
            fi
        fi

        printDebug "Working Directory : $(pwd)"
        if [[ ${g_bInsideGitRepo} = true ]];then
            printDebug "Root branch    : $g_sRootBranch"
            printDebug "Current branch : $(getCurrentBranch)"
        else
            printDebug "Not in a git repo"
        fi

        runCleanup

        printMessage 'Done.'
    fi

    exit ${g_iExitCode}
}

debugTrapMessage() {
    printDebug "${g_sColorDim}[${1}:${2}] ${3}${g_sColorRestore}"
}

registerTraps() {
    trap finish EXIT
    trap finish ERR
}

registerDebugTrap() {
    if [[ "${DEBUG_LEVEL}" -gt 1 && "${DEBUG_LEVEL}" -lt 5 ]];then
        # Trap function is defined inline so we get the correct line number
        #trap '(echo -e "#[DEBUG] [$(basename ${BASH_SOURCE[0]}):${LINENO[0]}] ${BASH_COMMAND}");' DEBUG
        trap '(debugTrapMessage "$(basename ${BASH_SOURCE[0]})" "${LINENO[0]}" "${BASH_COMMAND}");' DEBUG
    fi
}
# ==============================================================================


# ==============================================================================
#                               RUN LOGIC
# ------------------------------------------------------------------------------
git-split-file() {
    export PS4='$(printf "%04d: " $LINENO)'

    registerTraps

    handleParams "${@}"

    registerDebugTrap

    if [[ "${DEBUG_LEVEL}" -gt 2 ]];then
        set -o xtrace   # Similar to -v, but expands commands, same as "set -x"
    fi

    if [[ ${g_iExitCode} -eq 0 ]];then

        if [[ "${g_bShowHelp}" = true ]];then
            fullUsage
        else
            run
        fi
    fi
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    export -f git-split-file
else
    git-split-file "${@}"
    exit $?
fi
# ==============================================================================

#EOF
