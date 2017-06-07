#!/bin/bash

################  
#
#   MapR Cluster Log/Disk/System Analyzer
#
#################
#set -x

# Library directory
basedir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
libdir=$basedir"/lib"
me=$(basename $BASH_SOURCE)
meid=$$

# Declare Variables
returncode=0
rolefile=
args=
tbltdist=
indexname=
sysinfo=
grepkey=
backupdir=
mfstracedir=
numiter=
mfscpuusedir=
gutsdir=
publishdesc=
startstr=
endstr=
backupregex=
verbose=
doNoFormat=

trap handleInterrupt SIGHUP SIGINT SIGTERM

function kill_tree {
    local LIST=()
    IFS=$'\n' read -ra LIST -d '' < <(exec pgrep -P "$1")

    for i in "${LIST[@]}"; do
        kill_tree "$i"
    done

    echo "kill -9 $1"
    kill -9 "$1" 2>/dev/null
}

function handleInterrupt() {
    echo
    echo " Script interrupted!!! Stopping... "
    local mainid=$(ps -o pid --no-headers --ppid $meid)
    echo "CHILD PROCESS ID : $mainid; Sending SIGTERM..."
    kill -15 $mainid 
    kill -9 $mainid 2>/dev/null
    kill_tree $meid
    echo "Bye!!!"
}

function usage () {
	echo 
	echo "Usage : "
    echo "./$me -c=<ClusterConfig> [Options]"
    echo
    echo -e "\t -c=<file> | --clusterconfig=<file>" 
    echo -e "\t\t - Cluster Configuration Name/Filepath"

    echo " Options : "
    echo -e "\t -h --help"
    echo -e "\t\t - Print this"

    echo -e "\t -fl | --noformat" 
    echo -e "\t\t - Remove output formatting (ANSI color)"

    echo -e "\t -d | --diskerror" 
    echo -e "\t\t - Find any disk errors on nodes"

    echo -e "\t -ac | --analyzecores" 
    echo -e "\t\t - Analyze cores present"

    echo -e "\t -v | --verbose" 
    echo -e "\t\t - Print verbose of messages"

    echo -e "\t -dt | --disktest" 
    echo -e "\t\t - Run 'hdparm' disk tests on all nodes for MapR disks"

    echo -e "\t -cd | --containerdist" 
    echo -e "\t\t - Check Container distribution across SPs on each node"

    echo -e "\t -td=<FILEPATH> | --tabletdist=<FILEPATH>" 
    echo -e "\t\t - Check Tablet distribution across SPs on each node for FILEPATH"

    echo -e "\t -in | --indexname= | -in=<INDEXNAME> | --indexname=<INDEXNAME>" 
    echo -e "\t\t - When passed with -td option, check INDEXNAME table's tablet distribution across nodes"

    echo -e "\t -si=<OPTIONS> | --systeminfo=<OPTIONS>" 
    echo -e "\t\t - Print system info of each node. OPTIONS : mapr,machine,cpu,disk,nw,mem or all (comma separated)"

    echo -e "\t -cs | --clusterspec" 
    echo -e "\t\t - Print overall cluster specifications"

    echo -e "\t -sc | --setupcheck" 
    echo -e "\t\t - Validate a cluster setup & the services"

    echo -e "\t -l | --mfsloggrep" 
    echo -e "\t\t - Grep mfs logs for FATAL & Disk errors"

    echo -e "\t -g=<SEARCHKEY> | --greplogs=<SEARCHKEY>" 
    echo -e "\t\t - Grep MapR logs for SEARCHKEY on all nodes"

    echo -e "\t -b | -b=<COPYTODIR> | --backuplogs=<COPYTODIR>" 
    echo -e "\t\t - Backup /opt/mapr/logs/ directory on each node to COPYTODIR (default COPYTODIR : /tmp/)"

    echo -e "\t -bf=<FILEREGEX> | --backupregex=<FILEREGEX>" 
    echo -e "\t\t - When passed with -b option, backup only log files with name matching the FILEREGEX"

    echo -e "\t -mt | -mt=<COPYTODIR> | --mfstrace=<COPYTODIR>" 
    echo -e "\t\t - Run gstack on MFS process on each node & copy trace files to COPYTODIR (default COPYTODIR : /tmp/)"

    echo -e "\t -it=<NUM> | --iterations=<NUM>" 
    echo -e "\t\t - When passed with -mt option, will run gstack for NUM iterations (default: 10)"

    echo -e "\t -mti | --mfsthreadinfo" 
    echo -e "\t\t - List MFS thread id details from all MFS nodes (works on new GLIBC versions only)"

    echo -e "\t -mcu | -mcu=<COPYTODIR> |--mfscpuuse=<COPYTODIR>" 
    echo -e "\t\t - Build consolidated MFS thread-wise CPU Use log (default COPYTODIR : /tmp/)"

    echo -e "\t -guts=<COPYTODIR>" 
    echo -e "\t\t - Build & copy consolidated guts stats from all MFS nodes to COPYTODIR"

    echo -e "\t -st=<STRING> | --starttime=<STRING>" 
    echo -e "\t\t - Specify start time STRING for -mcu or -guts option "

    echo -e "\t -et=<STRING> | --endtime=<STRING>" 
    echo -e "\t\t - Specify end time STRING for -mcu or -guts option "

    echo -e "\t -pub | -pub=<DESCRIPTION> | --publish=<DESCRIPTION>" 
    echo -e "\t\t - When used with -mcu or -guts option, publish stats to Dashboard (dash.perf.lab)"

    echo -e "\t -gwguts" 
    echo -e "\t\t - When passed with -guts option, build gateway guts instead of mfs"
    
    echo 
    echo " Examples : "
    echo -e "\t ./mapr_logdr.sh -c=maprdb -d -l"
    echo -e "\t ./mapr_logdr.sh -c=maprdb -td=/tables/usertable -cd"
    echo -e "\t ./mapr_logdr.sh -c=maprdb -b=~/logsbkp/ -bf=\"*mfs*\""
    echo -e "\t ./mapr_logdr.sh -c=maprdb -si -cs"
    echo -e "\t ./mapr_logdr.sh -c=maprdb -si -fl > /tmp/sysinfo.log"
    echo -e "\t ./mapr_logdr.sh -c=maprdb -sc"
    echo -e "\t ./mapr_logdr.sh -c=maprdb -g=\"error 5\""
    echo -e "\t ./mapr_logdr.sh -c=10.10.103.[165,171-175] -mt=/tmp/mfstrace -it=20"
    echo -e "\t ./mapr_logdr.sh -c=maprdb -mti"
    echo -e "\t ./mapr_logdr.sh -c=10.10.103.171 -mcu=/tmp/mfscpuuse -st=\"13:00:00\" -et=\"15:00:00\" -pub=\"YCSB-LOAD\""
    echo -e "\t ./mapr_logdr.sh -c=10.10.103.[171-175] -guts=/tmp/gutsstats -pub=\"PONTIS-6.0\""
    echo -e "\t ./mapr_logdr.sh -c=10.10.103.[171-175] -mcu=/tmp/cdcmfs -guts=/tmp/cdcguts -pub=\"CDC JSON\" -st=\"2017-06-01 11:00\" -et=\"2017-06-06 13:00\""
    echo
}

while [ "$1" != "" ]; do
    OPTION=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    #echo "OPTION -> $OPTION ; VALUE -> $VALUE"
    case $OPTION in
        -h | h | help)
            usage
            exit
            ;;
        -c | --clusterconfig)
            rolefile=$VALUE
        ;;
    	-d | --diskerror)
    		args=$args"diskerror "
    	;;
        -ac | --analyzecores)
            args=$args"analyzecores "
        ;;
        -dt | --disktest)
            args=$args"disktest "
        ;;
        -cs | --clusterspec)
            args=$args"clsspec "
        ;;
        -sc | --setupcheck)
            args=$args"setupcheck "
        ;;
        -cd | --containerdist)
            args=$args"cntrdist "
        ;;
        -td | --tabletdist)
            if [ -n "$VALUE" ]; then
                args=$args"tabletdist "
                tbltdist="$VALUE"
            fi
        ;;
        -in | --indexname)
            if [ -n "$VALUE" ]; then
                indexname="$VALUE"
            else
                indexname="all"
            fi
        ;;
        -b | --backuplogs)
            if [ -z "$VALUE" ]; then
                VALUE="/tmp"
            fi
            backupdir=$VALUE
        ;;
        -bf | --backupregex)
            [ -n "$VALUE" ] && backupregex=$VALUE
        ;;
        -mt | --mfstrace)
            if [ -z "$VALUE" ]; then
                VALUE="/tmp"
            fi
            mfstracedir=$VALUE
            args=$args"mfstrace "
        ;;
        -mti | --mfsthreadinfo)
            args=$args"mfsthreads "
        ;;
        -it | --iterations)
            numiter=$VALUE
        ;;
        -mcu | --mfscpuuse)
            if [ -z "$VALUE" ]; then
                VALUE="/tmp"
            fi
            mfscpuusedir=$VALUE
            args=$args"mfscpuuse "
        ;;
        -st | --starttime)
            if [ -n "$VALUE" ]; then
                startstr="$VALUE"
            fi
        ;;
        -et | --endtime)
            if [ -n "$VALUE" ]; then
                endstr="$VALUE"
            fi
        ;;
        -pub | --publish)
            if [ -n "$VALUE" ]; then
                publishdesc="$VALUE"
                args=$args"publish "
            fi
        ;;
        -guts)
            if [ -n "$VALUE" ]; then
                gutsdir=$VALUE
                args=$args"gutsstats "
            fi
        ;;
        -gwguts)
            args=$args"gwguts "
        ;;
        -defguts)
            args=$args"defaultguts "
        ;;
        -si | --systeminfo)
            sysinfo="$VALUE"
            if [ -z "$sysinfo" ]; then
                sysinfo="all"
            fi
        ;;
        -g | --greplogs)
            if [ -n "$VALUE" ]; then
                grepkey="$VALUE"
            fi
        ;;
        -l | --mfsloggrep)
            args=$args"mfsgrep "
        ;;
        -v | --verbose)
            verbose=1
        ;;
        -fl)
            doNoFormat=1
        ;;
        *)
            #echo "ERROR: unknown option \"$OPTION\""
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$rolefile" ]; then
	echo "[ERROR] : Cluster config not specified. Please use -c or --clusterconfig option. Run \"./$me -h\" for more info"
	returncode=1
else
    params="$libdir/main.sh $rolefile -td=$tbltdist -in=${indexname} -si=$sysinfo -v=$verbose \"-e=force\" \
    \"-g=$grepkey\" \"-b=$backupdir\" \"-bf=$backupregex\" \"-l=$args\" \"-mt=$mfstracedir\" \"-it=$numiter\" \
    \"-mcu=$mfscpuusedir\" \"-st=$startstr\" \"-et=$endstr\" \"-pub=$publishdesc\" \"-guts=$gutsdir\""
    if [ -z "$doNoFormat" ]; then
        bash -c "$params"
    else
        bash -c "$params" | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g'
    fi
    returncode=$?
fi

exit $returncode
