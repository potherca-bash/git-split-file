#!/usr/bin/env bash

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
##         Can be one of DELETE | KEEP | MOVE
##
## Call --help for more details
##
#/ Usually when you want to split a file into several files under git, you would
#/ lose the git history of this file. Often this is not desirable. The goal of
#/ this script is to enable splitting one file under Git revision control into
#/ multiple files whilst keeping the files git history intact.
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
#/  0  : Everything OK
#/ 64  : Undefined Error
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
readonly g_sBranchPrefix='split-file'
# ==============================================================================


# ==============================================================================
#                           IMPORT EXTERNAL FUNCTIONS
# ------------------------------------------------------------------------------
function importDependencies() {

    source "${HOME}/.common.sh"

    sourceFunction debug error indent message outputErrorMessages printRuler printStatus printTopic usage
}
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
function handleParams {

    for sParam in ${*};do
        if [ "${sParam}" = "--help" ];then
            g_bShowHelp=true
        fi
    done

    if [ "${g_bShowHelp}" = false ] && [  "$#" -ne 4 ];then
        g_iExitCode=65
        error 'This script expects four command-line arguments'
    elif [ "${g_bShowHelp}" = false ];then
        readonly g_sTargetDirectory="${3}"
        readonly  g_sStrategy="${4}"

        if [ ! -f $(readlink -f "${1}") ];then
            g_iExitCode=66
            error "The given root file '${1}' does not exist"
        else
            readonly g_sSourceFilePath=$(readlink -f "${1}")
            readonly g_sSourceFileName=$(basename "${g_sSourceFilePath}")

            if [ "$(git status ${g_sSourceFilePath} > /dev/null 2>&1 || echo '1')" ];then
                g_iExitCode=67
                error "The given split file '${g_sSourceFilePath}' is not part of a git repository"
            else
                g_bInsideGitRepo=true
                readonly g_sRootBranch=$(getCurrentBranch)
                readonly g_sSourceBranch="${g_sBranchPrefix}_${g_sSourceFileName}"
            fi
        fi

        if [ ! -e $(readlink -f "${2}") ];then
            g_iExitCode=68
            error "The given split directory '${2}' does not exist"
        elif [ ! -d $(readlink -f "${2}") ];then
            g_iExitCode=69
            error "The given split directory '${2}' is not a directory"
        else
            readonly g_sSplitDirectory=$(readlink -f "${2}")
        fi

        if [ "${g_sStrategy}" != 'DELETE' ] && [ "${g_sStrategy}" != 'KEEP' ] && [ "${g_sStrategy}" != 'MOVE' ]; then
            g_iExitCode=71
            error "The given split strategy '${g_sStrategy}' is not one of supported DELETE | KEEP | MOVE"
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
    printStatus 'Creating commit'
    git commit -m "${1}." | indent
}

function createBranch() {
    local sBranchName sStartBranch

    sBranchName="${1}"
    sStartBranch="${2}"

    #git checkout -b "${sBranchName}" "${sStartBranch}" | indent
    git branch "${sBranchName}" "${sStartBranch}" | indent
}

function createSourceBranch() {
    printTopic 'Creating separate branch to merge split files back into'
    createBranch "${g_sSourceBranch}" "${g_sRootBranch}"
}

function createSplitBranch() {
    printStatus "Creating separate branch to split file '${1}'"
    createBranch "${g_sSourceBranch}_${1}" "${g_sSourceBranch}"
}

function checkoutBranch() {
    printStatus "Switching back to ${2} branch"
    git checkout "${1}" | indent
}

function checkoutSplitBranch() {
    local sBranchName sFile

    sFile="${1}"
    sBranchName="${g_sSourceBranch}_${sFile}"

    checkoutBranch "${sBranchName}" 'split'
}

function checkoutRootBranch() {
    checkoutBranch "${g_sRootBranch}" 'root'
}

function checkoutSourceBranch() {
    checkoutBranch "${g_sSourceBranch}" 'source'
}

function mergeSplitBranch() {
    local sBranchName sFile
    local -i iResult=0
    sFile="${1}"

    sBranchName="${g_sSourceBranch}_${sFile}"

    printTopic "Merging branch '${sBranchName}' back into '$(getCurrentBranch)'"

    if [ -n "$(git show-ref refs/heads/${sBranchName})" ]; then
        printStatus "Branch '${sBranchName}' exists"
        git merge --no-ff --no-edit -X theirs ${sBranchName} | indent || iResult="$?"

        if [ "${iResult}" -eq 0 ]; then
            printStatus 'No merge conflict'
        else
            printStatus 'Merge conflict occurred. Attempting to resolve.'
            git add -- "${g_sSourceFilePath}" | indent

            commit "Merging split file '${g_sSourceFileName}'"
        fi
    else
        printStatus "Branch does not exist. No need to merge"
    fi
}

function renameFile() {
    local sFile="${1}"

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
        git mv "${g_sSourceFilePath}" "${g_sTargetDirectory}/${sFile}" | indent
        commit "Adds separate file for '${sFile}'"
    fi
}

function commitFileContent() {
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
    git add "${sTargetFile}" | indent
    commit "${sMessage}"
}

function createSubBranches() {
    local sFile

    printTopic 'Creating sub-branches'
    for sFile in $(ls "${g_sSplitDirectory}");do
        #if [[ "${sFile}" = "${g_sSourceFileName}" ]];then
        #    printStatus "Skipping branch for source file '${g_sSourceFileName}'"
        #else
            createSplitBranch "${sFile}"
        #fi
    done
}

function splitFiles() {
    local sFile

    for sFile in $(ls "${g_sSplitDirectory}");do
        #if [[ "${sFile}" = "${g_sSourceFileName}" ]];then
        #    printStatus "Skipping source file '${g_sSourceFileName}'"
        #else
            printTopic "Running split processing for file '${sFile}'"
            checkoutSplitBranch "${sFile}"
            renameFile "${sFile}"
            commitFileContent "${sFile}"
        #fi
    done
}

function mergeSplitBranches() {
    local sFile
    printTopic 'Merging all the split branches into the source branch'
    checkoutSourceBranch

    for sFile in $(ls "${g_sSplitDirectory}");do
        if [[ "${sFile}" = "${g_sSourceFileName}" ]];then
            printTopic "Skipping source file '${g_sSourceFileName}'"
        else
            printTopic "Running merge processing for file '${sFile}'"
            mergeSplitBranch "${sFile}"
        fi
    done

    printTopic 'All file-split branches have been merged into the main split branch'
}

function runCleanup() {
    local sBranchName sFile

    read -n1 -p 'Remove all created branches? (y/n) ' sContinue
    echo ""

    if [[ "${sContinue}" = 'y' ]];then
        printStatus 'Removing all the split branches that were created'

        git branch -D "${g_sSourceBranch}" | indent

        for sFile in $(ls "${g_sSplitDirectory}");do
            sBranchName="${g_sSourceBranch}_${sFile}"
            if [ -n "$(git show-ref refs/heads/${sBranchName})" ]; then
                # Branch exists
                git branch -D "${sBranchName}" | indent
            fi
        done
        sBranchName="${g_sSourceBranch}_${g_sSourceFileName}"
        if [ -n "$(git show-ref refs/heads/${sBranchName})" ]; then
            # Branch exists
            git branch -D "${sBranchName}" | indent
        fi

    else
        printStatus 'Leaving all branches in place.'
    fi

    printRuler 2
}

function outputHeader() {

    message "               running $0"
    message "       for source file ${g_sSourceFilePath}"
    message " with source directory ${g_sSplitDirectory}"
    message "   to target directory ${g_sTargetDirectory}"
    message "  using split strategy ${g_sStrategy}"

    debugMessage "g_sRootBranch      = ${g_sRootBranch}"
    debugMessage "g_sSourceBranch     = ${g_sSourceBranch}"
    debugMessage "g_sSourceFilePath  = ${g_sSourceFilePath}"
    debugMessage "g_sSourceFileName  = ${g_sSourceFileName}"
    debugMessage "g_sSplitDirectory  = ${g_sSplitDirectory}"
    debugMessage "g_sTargetDirectory = ${g_sTargetDirectory}"
    debugMessage "g_sStrategy        = ${g_sStrategy}"
}

function run() {

    outputHeader

    if [ "${DEBUG_LEVEL}" -gt 0 ];then
        printStatus "Debugging on - Debug Level : ${DEBUG_LEVEL}"
    fi

    read -n1 -p 'Does this look correct? (y/n) ' sContinue
    echo ""

    if [[ "${sContinue}" = 'y' ]];then
        createSourceBranch

        # Process all non-source files
        createSubBranches
        splitFiles

        # ---
        # @TODO: Utilize the strategy flag.
        # ---
        #printTopic "Running split process for source file '${g_sSourceFileName}'"
        #checkoutSourceBranch
        #commitFileContent "${g_sSourceFileName}"

        mergeSplitBranches
        # @NOTE: If a branch for g_sSourceFileName is present we need to merge that last
        mergeSplitBranch "${g_sSourceFileName}"

        printTopic "Merging source branch '${g_sSourceBranch}' into the root branch '${g_sRootBranch}'"
        checkoutRootBranch
        git merge --no-ff --no-edit "${g_sSourceBranch}" | indent
    else
        message 'Aborting.'
    fi
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
        debugMessage "Root branch    : $g_sRootBranch"
        debugMessage "Current branch : $(getCurrentBranch)"
    else
        debugMessage "Not in a git repo"
    fi

    if [ ${g_bInsideGitRepo} = true ] && [  "${g_sRootBranch}" != "$(getCurrentBranch)" ] ;then
        checkoutRootBranch
    fi

    runCleanup

    message 'Done.'

    exit ${g_iExitCode}
}

function registerTraps() {

    trap finish EXIT
    trap finish ERR

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
handleParams ${@:-}

if [ ${g_iExitCode} -eq 0 ];then

    if [ "${g_bShowHelp}" = true ];then
        fullUsage
    else
        run
    fi
fi
# ==============================================================================
#EOF
