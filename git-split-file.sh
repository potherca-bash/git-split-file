#!/usr/bin/env bash
#/==============================================================================
#/                               GIT SPLIT FILE
#/------------------------------------------------------------------------------
## Usage: git.split.sh <root-file> <result-path>
##
## Where <root-file> is the file in a git repository you would like to be split
## and result-path is the directory that holds the result of how you would like
## things to be after the file has been split. Call --help for more details
##
#
#/ Usually when you want to split a file into several files under git, you would
#/ lose the git history of this file. Often this is not desirable. The goal of
#/ this script is to enable splitting one file under Git revision control into
#/ multiple files whilst keeping the files git history intact.
#/
#/ For this script to work, you need to first create a folder that contains the
#/ end result you want. This means you need to manually split the content of the
#/ file you want to keep into seperate files. The more of the order and
#/ whitespace you leave intact, the more of the history will also be left intact.
#
#/ Once you have everything to your liking, you point this script to the file you
#/ want to split and the folder that holds the desired end result.
#/
#/ This script will then branch of from the branch the designated git repo is on
#/ for each file to split into. It will then split the given root file, commit
#/ the split result and merge it back to the branch it was originally on.
#/ ------------------------------------------------------------------------------
#/ The following ExitCodes are used:
#/
#/  0  : Everything OK
#/ 64  : Undefined Error
#/
#/ 65 : Not enough parameters given
#/ 66 : The given root file does not exist
#/ 67 : The given root file is not part of a git repository
#/ 68 : Given split directory path does not exist
#/ 69 : Given split directory path is not a directory
#/
# Please note that g_iExitCode needs to be set *before* error() is called,
# otherwise the ExitCode will default to 64.
# ------------------------------------------------------------------------------
# Apparently the idea of the 'execute' function is a bit of an anti-pattern.
# (see http://mywiki.wooledge.org/BashFAQ/050). So either we need to ammend this
# construction, use 'set -x', copy/past/echo every command, or try if using
# 'trap [...] DEBUG' is workable OR we should just let go of the idea of the
# one-on-one replayable log.
# @FIXME: Replace `execute` calls with a better solution
#/==============================================================================


# ==============================================================================
#                               CONFIG VARS
# ------------------------------------------------------------------------------
# DEBUG_LEVEL 0 = No Debugging
# DEBUG_LEVEL 1 = Show Debug messages
# DEBUG_LEVEL 2 = " and show Application Calls
# DEBUG_LEVEL 3 = " and show called command
# DEBUG_LEVEL 4 = " and show all other commands (=set +x)
# DEBUG_LEVEL 5 = Show All Commands, without Debug Messages or Application Calls

readonly DEBUG_LEVEL=0
# ==============================================================================


# ==============================================================================
#                                APPLICATION VARS
# ------------------------------------------------------------------------------
# For all options see http://www.tldp.org/LDP/abs/html/options.html
set -o nounset      # Exit script on use of an undefined variable, same as "set -u"
set -o errexit      # Exit script when a command exits with non-zero status, same as "set -e"
set -o pipefail     # Makes pipeline return the exit status of the last command in the pipe that failed

if [ "${DEBUG_LEVEL}" -gt 2 ];then
    set -o xtrace   # Similar to -v, but expands commands, same as "set -x"
fi

declare g_bInsideGitRepo=false
declare g_bShowHelp=false
declare -a g_aErrorMessages
declare -i g_iExitCode=0
declare -i g_iErrorCount=0
# ==============================================================================


# ==============================================================================
#                           IMPORT EXTERNAL FUNCTIONS
# ------------------------------------------------------------------------------
function importDependencies() {

    source "${HOME}/.common.sh"

    sourceFunction debug error execute message outputErrorMessages printRuler usage
}
# ==============================================================================


# ==============================================================================
# Sets script variables based on input, when valid.
#
# The following variables will be set:
#
# - g_bInsideGitRepo
# - g_bShowHelp
# - g_sRootBranch
# - g_sRootDirectory
# - g_sRootFileName
# - g_sRootFilePath
# - g_sSplitBranch
# - g_sSplitDirectory
#
# ------------------------------------------------------------------------------
function handleParams {

    for sParam in ${*};do
        if [ "${sParam}" = "--help" ];then
            g_bShowHelp=true
        fi
    done

    if [ "${g_bShowHelp}" = false ] && [  "$#" -ne 2 ];then
        g_iExitCode=65
        error 'This script expects two command-line arguments'
    elif [ "${g_bShowHelp}" = false ];then
        readonly g_sRootFilePath=$(readlink "${1}")
        readonly g_sRootFileName=$(basename "${g_sRootFilePath}")
        readonly g_sSplitDirectory=$(readlink "${2}")

        if [ ! -f $(readlink "${g_sRootFilePath}") ];then
            g_iExitCode=66
            error "The given root file '${g_sRootFilePath}' does not exist"
        else
            readonly g_sRootDirectory=$(dirname "${g_sRootFilePath}")

            cd "${g_sRootDirectory}" # @FIXME: <--- Using `cd` is a side-effect!

            if [ $(git status $(readlink "${1}") > /dev/null 2>&1 || echo '1') ];then
                g_iExitCode=67
                error "The given split file '${1}' is not part of a git repository"
            else
                g_bInsideGitRepo=true
                readonly g_sRootBranch=$(getCurrentBranch)
                readonly g_sSplitBranch="split-file-${g_sRootFileName}"
            fi
        fi

        if [ ! -e $(readlink "${g_sSplitDirectory}") ];then
            g_iExitCode=68
            error "The given split directory '${g_sSplitDirectory}' does not exist"
        elif [ ! -d $(readlink "${g_sSplitDirectory}") ];then
            g_iExitCode=69
            error "The given split directory '${g_sSplitDirectory}' is not a directory"
        fi
    fi
    return ${g_iExitCode}
}
# ==============================================================================

# ##############################################################################
#                              UTILITY FUNCTIONS
# ##############################################################################
function debugMessage() {
    if [ "${DEBUG_LEVEL}" -gt 0 ] && [ "${DEBUG_LEVEL}" -lt 5 ];then
        debug "${1}"
    fi
}

function getCurrentBranch() {
    echo $(git rev-parse --abbrev-ref HEAD)
}

function commit() {
    echo "git commit -m \"${1}\""
    git commit -m "${1}"
}

function createSubBranch() {
    execute "git checkout -b ${g_sSplitBranch}_${1}"
}

function checkoutBranch() {
    printRuler 3
    message "Switching back to ${2} branch"
    printRuler 3
    execute "git checkout ${1}"
    message "Current branch : $(getCurrentBranch)"
}

function checkoutRootBranch() {
    checkoutBranch "${g_sRootBranch}" 'original'
}

function checkoutSplitBranch() {
    checkoutBranch "${g_sSplitBranch}" 'split'
}

function createSplitBranch() {
    printRuler 2
    message 'Creating separate branche to merge split files back into'
    printRuler 3
    execute "git checkout -b ${g_sSplitBranch}"
    printRuler 2
    echo ''
}

function mergeSplitBranch() {
    local sSplitFile="${1}"
    local -i iResult=0
    printRuler 3
    message "Current branch : $(getCurrentBranch)"
    message "  Current file : ${sSplitFile}"
    git merge -X theirs ${g_sSplitBranch}_${sSplitFile} || iResult="$?"

    if [ "${iResult}" -eq 0 ]; then
        message 'No merge conflict'
    else
        message 'Merge conflict occurred. Attempting to resolve.'
        execute "git add -- ${g_sRootFileName}"

        # @TODO: Figure out when we can just use `commit -F '.git/COMMIT_EDITMSG'`
        commit "Merging split file '${g_sRootFileName}'"
    fi
}

function renameFile() {
    local sNewFile="${1}"

    if [ "${g_sRootFileName}" = "${sNewFile}" ];then
        message "File is root file '${g_sRootFileName}', no need to rename"
    else
        execute "git mv ${g_sRootFileName} ${sNewFile}"
        commit "Creates separate file for '${sNewFile}'"
    fi
}

function moveFileContent() {
    local sFile="${1}"
    local sMessage

    echo "cat ${g_sSplitDirectory}/${sFile} > ${g_sRootDirectory}/${sFile}"
    cat "${g_sSplitDirectory}/${sFile}" > "${g_sRootDirectory}/${sFile}"

    execute "git add ${sFile}"

    if [ "${g_sRootFileName}" = "${sFile}" ];then
        sMessage="Removes all content from '${sFile}' that has been moved to separate file(s)"
    else
        sMessage="Places content for '${sFile}' in separate file"
    fi

    commit "${sMessage}"
}

function runSplit() {

    createSplitBranch

    for sSplitFile in $(ls "${g_sSplitDirectory}");do
        printRuler 2
        message "Splitting for ${sSplitFile}"
        printRuler 3

        createSubBranch "${sSplitFile}"
        renameFile "${sSplitFile}"
        moveFileContent "${sSplitFile}"
        checkoutSplitBranch

        printRuler 2
        echo ''
    done
}

function runMerges() {

    printRuler 2
    message 'Merging all the file-split branches into the main split branch'

    # @NOTE: If a branch for g_sRootFileName is present we need to merge that last
    for sSplitFile in $(ls "${g_sSplitDirectory}");do
        if [ "${sSplitFile}" != "${g_sRootFileName}" ];then
            mergeSplitBranch "${sSplitFile}"
        fi
    done

    mergeSplitBranch "${g_sRootFileName}"

    checkoutRootBranch
    printRuler 2
    echo ''

    printRuler 2
    message 'Merging split branch into the root branch'
    printRuler 3
    execute "git merge ${g_sSplitBranch}"
    printRuler 2
    echo ''
}

function runCleanup() {
    printRuler 2
    message 'Remove all the split branches that were created'
    printRuler 3

    execute "git branch -D ${g_sSplitBranch}"

    for sSplitFile in $(ls "${g_sSplitDirectory}");do
        execute "git branch -D ${g_sSplitBranch}_${sSplitFile}"
    done
    printRuler 2
}

function outputHeader() {
    printRuler 2
    message "        running $0"
    message "       for file ${g_sRootFilePath}"
    message " with directory ${g_sSplitDirectory}"
    printRuler 3
    debugMessage "g_sRootBranch     = ${g_sRootBranch}"
    debugMessage "g_sSplitBranch    = ${g_sSplitBranch}"
    debugMessage "g_sRootFileName   = ${g_sRootFileName}"
    debugMessage "g_sRootDirectory  = ${g_sRootDirectory}"
    debugMessage "g_sRootFilePath   = ${g_sRootFilePath}"
    debugMessage "g_sSplitDirectory = ${g_sSplitDirectory}"
    printRuler 2
    echo ''
}

function run() {

    outputHeader

    if [ "${DEBUG_LEVEL}" -gt 0 ];then
        message "Debugging on - Debug Level : ${DEBUG_LEVEL}"
    fi
    runSplit
    runMerges
    runCleanup
}

function finish() {
    if [ ! ${g_iExitCode} -eq 0 ];then
        outputErrorMessages ${g_aErrorMessages[*]}

        if [ ${g_iExitCode} -eq 65 ];then
            usage
        fi
    fi

    debugMessage "Working Directory : $(pwd)"
    if [ ${g_bInsideGitRepo} = true ];then
        debugMessage "Current branch : $(getCurrentBranch)"
    else
        debugMessage "Not in a git repo"
    fi

    if [ ${g_bInsideGitRepo} = true ] && [  "${g_sRootBranch}" != "$(getCurrentBranch)" ] ;then
        checkoutRootBranch
    fi

    exit ${g_iExitCode}
}

function registerTraps() {
    trap finish EXIT
    if [ "${DEBUG_LEVEL}" -gt 1 ] && [ "${DEBUG_LEVEL}" -lt 5 ];then
        # Trap function is defined inline so we get the correct line number
        #trap '(echo -e "#[DEBUG] [$(basename ${BASH_SOURCE[0]}):${LINENO[0]}] ${BASH_COMMAND}");' DEBUG
        trap '(debugTrapMessage "$(basename ${BASH_SOURCE[0]})" "${LINENO[0]}" "${BASH_COMMAND}");' DEBUG
    fi
}
# ==============================================================================


# ==============================================================================
#                               RUN LOGIC
# ------------------------------------------------------------------------------
importDependencies
registerTraps
handleParams VALUE=${@:-}

if [ ${g_iExitCode} -eq 0 ];then

    if [ "${g_bShowHelp}" = true ];then
        fullUsage
    else
        run
    fi

    if [ ${#g_aErrorMessages[*]} -ne 0 ];then
        outputErrorMessages "${g_aErrorMessages[*]}"
    else
        message 'Done.'
    fi
fi
# ==============================================================================
#EOF