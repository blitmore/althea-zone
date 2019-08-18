#!/bin/bash

##
## USE AT YOUR OWN RISK, run via cron.
## 
## Run this script as the user running gaiad.
## If you want to try it before the repo is in order,
## make a fake altheatest3-to-altheatest4.py file:
##
##   cd <your althea-zone> 
##   echo "X" > altheatest3-to-altheatest4.py
## 
## Remove that file when done. 
##
##
## NOTES: 
##       This script is furnished only partially enabled -
##       based on the value of 'forkingBlock' (currently
##       set for a time in the past) , it will
##       kill your running gaiad and crank up a new instance
##       with the output piped to ${HOME}/gaiad.log. To make
##       this fully operable look for and act on the the 
##       lines marked: 
##      
##       ## UNCOMMENT when you are really ready to go
##
##       ... AND make sure the DEBUG forkingBlock IS COMMENTED.
##       
##       Also, ${tmpdir} contains backup of genesis.json
##
## Check that the following vars are correctly set.

## Althea repo
altheazone="https://github.com/althea-net/althea-zone"

## Your clone of the above
altheazone_srcdir="/home/althea/src/Althea/althea-zone"

## gaiad thinks it is running here, aka full path to altheatest3 genesis.json
genesis_file="${HOME}/.gaiad/config/genesis.json"

## gonna assume python3? for manipulation of genesis.json .
## 
python=`which python3`


##
## Maybe we ought to back up the old genesis for some reason...
## and not lose the original altheatest3 genesis should we run this 
## script more than once.
##
tmpdir="${HOME}/altheatest3_2_altheatest4"

if [ -d ${tmpdir} ] 
then
    now=`date +"%s"`
    cp ${genesis_file} ${tmpdir}/${now}_genesis.json
else
    mkdir ${tmpdir}
    cp ${genesis_file} ${tmpdir}/altheatest3_genesis.json
fi


##
## From the althea-zone README.md:
##
########################################
## Step 1
## On or after August 19th, 3pm PDT, 
## check this readme at https://github.com/althea-net/althea-zone 
## for the correct block height to fork at. It will appear below:
## FORKING BLOCK: <to be determined>
########################################
echo " STEP1 -- prelude"

##
## Figure out forkingBlock
##

## maybe you like to determine via curl for some reason...
#forkingBlock=`curl -v --silent "${altheazone}" 2>&1|grep 'FORKING BLOCK'|tr ' ' '\n'|egrep '[[:digit:]]{6}'`
#echo "  FORKING BLOCK (via curl) is ${forkingBlock}"

##
## ...but prolly best after a pull, from the README.md itself. 
##
cd "${altheazone_srcdir}" || exit
echo "  bout to update althea-zone codebase..."
git pull 

##
## We also assume that
##  'FORKING BLOCK: <to be determined>'
## will be replaced with 
##  'FORKING BLOCK: 6-or-more-digits'
## 
forkingBlock=`grep 'FORKING BLOCK' ./README.md|tr ' ' '\n'|egrep '^[[:digit:]]{6,}'`
echo "  FORKING BLOCK (README.md) is ${forkingBlock}"

## DEBUGGERY
## a past block
forkingBlock=146470
## a far-future block
#forkingBlock=500000

## Bail should we prove unable to figure out the forkingBlock on which to trigger
[[ -z ${forkingBlock} ]] && { echo "FAILED to get anything for forkingBlock, maybe not yet posted?" && exit; : ;} 

echo "  FORKING BLOCK is ${forkingBlock}"

## State check- grab the highest block gaiad has seen, no sense proceeding if unable.
currentBlock=`gaiacli status --chain-id=altheatest3|tr ',' '\n'|grep 'hei'|tr -d '"'|cut -d: -f2`
[[ -z ${currentBlock} ]] && { echo "FAILED to get anything for currentBlock, gaiad running?" && exit; : ;} 

echo "  Current BLOCK is ${currentBlock}"

## Time for action?
[[ "${currentBlock}" -ge "${forkingBlock}" ]] || { echo "still too early, exiting" && exit; : ;}


## Bail if the python update utility for genesis.json is missing.
[[ -s altheatest3-to-altheatest4.py ]] || { echo "  altheatest3-to-altheatest4.py does not exist or is empty? BAILING." && exit; : ;}



########################################
## Step 2
## Stop any existing gaiad process and run 
## gaiad export --for-zero-height --height=<forking block from step 1 above> > altheatest3_genesis_export.json
########################################
echo " STEP2 -- stop gaiad on altheatest3"

gaiad_pid=`ps -C gaiad --no-header -o pid`

## Stop altheatest3 gaiad process
while ! [ -z ${gaiad_pid} ]
do
    echo "  attempting to stop altheatest3 gaiad on ${gaiad_pid}"
    /bin/kill -15 "${gaiad_pid}"
    sleep 2

    gaiad_pid=`ps -C gaiad --no-header -o pid`
done


## UNCOMMENT when you are really ready to go
#gaiad export --for-zero-height --height=${forkingBlock} > altheatest3_genesis_export.json



########################################
#Step 3
## Run python altheatest3-to-altheatest4.py altheatest3_genesis_export.json > genesis.json 
## to make the neccesary changes to the genesis file. 
## altheatest3-to-altheatest4.py will appear in this repo before August 19th, 3pm PDT.
########################################
echo " STEP3 -- update genesis.json from altheatest3 to altheatest4"

## UNCOMMENT when you are really ready to go
#${python3} altheatest3-to-altheatest4.py altheatest3_genesis_export.json > ${genesis_file}




########################################
## Step 4
## Run gaiad unsafe-reset-all and then 
## gaiad start --p2p.persistent_peers "20d682e14b3bb1f8dbdb0492ea5f401c0c088163@198.245.51.51:26656" 
## to hopefully start on the new chain!
########################################
echo " STEP4 -- restart gaiad on altheatest4"

## UNCOMMENT when you are really ready to go
#gaiad unsafe-reset-all 
(gaiad start --p2p.persistent_peers "20d682e14b3bb1f8dbdb0492ea5f401c0c088163@198.245.51.51:26656" &>> ${HOME}/gaiad.log) &
gaiad_pid=`ps -C gaiad --no-header -o pid`
echo "  gaiad running at pid ${gaiad_pid}"

