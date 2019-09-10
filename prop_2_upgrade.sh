#!/usr/bin/env bash

##
## Run this script as the user running gaiad.
##
## Assumptions:
##   1. linux, bash, cp, which, kill, python3 etc. 
##      are available.
##   2. your version of golang is recent, will
##      build gaiad/gaiacli and is in your path.
##      We do a bit of looking into this, but not 
##      much. See 'GOPATH' below.
##
##   3. 
##
##
## Check that the following are correctly set:
##
## Fork specifics
## FIXME:
forkingBlock=260785
prefork_chain='altheatest4'
postfork_chain='altheatest5'
## known good peers
## Justin
ppeer_00='20d682e14b3bb1f8dbdb0492ea5f401c0c088163@198.245.51.51:26656'


## gaia branch intended for this fork
BRANCH='master'

## expected version, post-build, of gaiad/gaiacli
VERSION='0.0.0-58-gd624ca1'

## gaiad thinks the genesis.json lives here
genesis_file="${HOME}/.gaiad/config/genesis.json"

## althea-zone repo
altheazone="https://github.com/althea-net/althea-zone"

## our clone of the althea-zone repo
altheazone_src="${HOME}/src/Althea/althea-zone"

## althea-zone genesis file update utility
## FIXME:
genesis_up="${altheazone_src}/genesis_up.py"

## gaiad/gaiacli repo
REPO='https://github.com/cosmos/gaia'

## our clone of the gaiad/gaiacli repo
gaia_src="${HOME}/src/Cosmos/gaia"

python=$(which python3)

## genesis backups and pre-fork gaiad/gaiacli
## end up here
tmpdir="${HOME}/prop2_upgrade"


########################################
## 
##  Build / Update gaiad and gaiacli
## 
########################################
[[ ${GOPATH} ]] || GOPATH=${HOME}/go
[[ $(echo ${PATH}|grep -E 'go/bin') ]] || export PATH=${PATH}:${GOPATH}/bin

gaiad_version=$(gaiad version)
gaiacli_version=$(gaiacli version)

if [ "X${gaiad_version}" != "X${VERSION}" ] || [ "X${gaiacli_version}" != "X${VERSION}" ]
then

    echo "Building gaiad and gaiacli..."

    if [ ! -d "${gaia_src}" ]
    then
	mkdir -p "${gaia_src%/*}" && cd ${gaia_src%/*}
	git clone ${REPO}
    fi

    cd "${gaia_src}"
    git checkout master && git pull

    ## Bail if we were unable to get on the right branch
    curBranch=$(git branch|grep -c "${BRANCH}")
    [[ "$curBranch" -eq 1 ]] || { echo "Error: unable to get on the proper gaiad branch" && exit; : ;}

    ## snag the v0.35.0 versions in case we need for some reason,
    ## dont overwrite if we launch this more than once
    now=$(date +"%s")
    cp $(which gaiad) "${tmpdir}/${now}_gaiad" 
    cp $(which gaiadcli) "${tmpdir}/${now}_gaiad" 

    make install

    gaiad_version=$(gaiad version)
    gaiacli_version=$(gaiacli version)

    ## Bail on version mismatch
    [[ "X${gaiad_version}" != "X${VERSION}" ]] && { echo " Error: correct gaiad version unavailable" && exit; : ;}
    [[ "X${gaiacli_version}" != "X${VERSION}" ]] && { echo " Error: correct gaiacli version unavailable" && exit; : ;}

fi


########################################
## 
##  Althea-zone 
## 
########################################
echo "Checking for genesis.json update utility..."

if [ ! -d "${altheazone_src}" ]
then
    mkdir -p "${altheazone_src%/*}" && cd ${altheazone_src%/*}
    git clone ${altheazone}
fi

cd ${altheazone_src}

## Bail if the python update utility is missing.
[[ -s ${genesis_up} ]] || { echo "  ${genesis_up} does not exist or is empty? BAILING." && exit; : ;}




########################################
## 
## Await the appointed block
## 
########################################
echo "  FORKING BLOCK is ${forkingBlock}"

## a past block
#forkingBlock=146470
## a future block
#forkingBlock=500000

currentBlock=$(gaiacli status --chain-id=${postfork_chain}|tr ',' '\n'|grep 'hei'|tr -d '"'|cut -d: -f2)

## Bail if gaiad is not running? Maybe we should just forge ahead? 
[[ -z ${currentBlock} ]] && { echo "FAILED to get anything for currentBlock, gaiad running?" && exit; : ;} 

echo "  Current BLOCK is ${currentBlock}"

while [ "${currentBlock}" -lt "${forkingBlock}" ] 
do
   echo "current block:${currentBlock}  - Awaiting block ${forkingBlock}" 
   sleep 5
   currentBlock=$(gaiacli status --chain-id=${postfork_chain}|tr ',' '\n'|grep 'hei'|tr -d '"'|cut -d: -f2)
done


########################################
## 
## Perform the fork
## 
########################################
echo "Performing the fork..."

##
## Back up the pre-fork genesis
## Do not overwrite in case we run this script more than once.
##
if [ -d "${tmpdir}" ] 
then
    now=$(date +"%s")
    cp "${genesis_file}" "${tmpdir}/${now}_genesis.json"
else
    mkdir "${tmpdir}"
    cp "${genesis_file}" "${tmpdir}/${prefork_chain}_genesis.json"
fi


########################################
## 
## Stop any existing gaiad process and run 
## 
########################################
echo " stopping ${prefork_chain} gaiad"

gaiad_pid=$(ps -C gaiad --no-header -o pid)

## Stop pre-fork gaiad process
while ! [ -z "${gaiad_pid}" ]
do
    echo "  attempting to stop ${prefork_chain} gaiad on ${gaiad_pid}"
    kill -15 "${gaiad_pid}"
    sleep 2

    gaiad_pid=$(ps -C gaiad --no-header -o pid)
done


########################################
## 
## export the pre-fork genesis file
## 
########################################
echo " exporting ${prefork_chain} genesis..."
gaiad export --for-zero-height --height=${forkingBlock} > "${tmpdir}/${prefork_chain}_genesis_export.json"


########################################
## 
## update the genesis file. 
## FIXME: can we use the new 'gaiad migrate' to do this?
########################################
echo " updating genesis.json from ${prefork_chain} to ${postfork_chain}"
${python} ${genesis_up} "${tmpdir}/${prefork_chain}_genesis_export.json" > ${genesis_file}


########################################
## 
## reset blockchain db, remove address book files and reset priv_validator.json 
## to the genesis state
## 
########################################
echo " resetting gaiad/config for genesis state..."
gaiad unsafe-reset-all 


########################################
## 
## hopefully start on the new chain
## 
########################################
echo " restarting gaiad on ${postfork_chain}"
(gaiad start --p2p.persistent_peers ${ppeer_00} &>> "${HOME}/${postfork_chain}_gaiad.log") &

gaiad_pid=$(ps -C gaiad --no-header -o pid)
echo "  gaiad version $(gaiad version) running at pid ${gaiad_pid}"
echo "  logging to ${HOME}/${postfork_chain}_gaiad.log"


## don't run this script again if we got this far and it was 
## launched via cron.
if ! [ -z "${gaiad_pid}" ]
then
    mv "${0}" "${0}_maybeSuceeded"
fi
