#!/bin/bash


################  
#
#   utilities
#
################

lib_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$lib_dir/utils.sh"
source "$lib_dir/ssh.sh"
source "$lib_dir/logger.sh"

### START_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###

## @param optional hostip
function maprutil_getCLDBMasterNode() {
    local master=
    local hostip=$(util_getHostIP)
    if [ -n "$1" ] && [ "$hostip" != "$1" ]; then
        #master=$(ssh_executeCommandWithTimeout "root" "$1" "maprcli node cldbmaster | grep HostName | cut -d' ' -f4" "10")
        master=$(ssh_executeCommandasRoot "$1" "[ -e '/opt/mapr/conf/mapr-clusters.conf' ] && cat /opt/mapr/conf/mapr-clusters.conf | cut -d' ' -f3 | cut -d':' -f1")
    else
        #master=$(timeout 10 maprcli node cldbmaster | grep HostName | cut -d' ' -f4)
        master=$([ -e '/opt/mapr/conf/mapr-clusters.conf' ] && cat /opt/mapr/conf/mapr-clusters.conf | cut -d' ' -f3 | cut -d':' -f1)
    fi
    if [ ! -z "$master" ]; then
            if [[ ! "$master" =~ ^Killed.* ]] || [[ ! "$master" =~ ^Terminate.* ]]; then
                echo $master
            fi
    fi
}

## @param path to config
function maprutil_getCLDBNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local cldbnodes=$(grep cldb $1 | grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$cldbnodes" ]; then
            echo $cldbnodes
    fi
}

## @param path to config
function maprutil_getESNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local esnodes=$(grep elastic $1 | grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$esnodes" ]; then
            echo $esnodes
    fi
}

## @param path to config
function maprutil_getOTSDBNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    local otnodes=$(grep opentsdb $1 | grep '^[^#;]' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$otnodes" ]; then
            echo $otnodes
    fi
}

## @param path to config
## @param host ip
function maprutil_getNodeBinaries() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    
    local binlist=$(grep $2 $1 | cut -d, -f 2- | sed 's/,/ /g')
    if [ ! -z "$binlist" ]; then
        echo $binlist
    fi
}

## @param path to config
## @param host ip
function maprutil_getCoreNodeBinaries() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    
    local binlist=$(grep $2 $1 | cut -d, -f 2- | sed 's/,/ /g')
    if [ -n "$binlist" ]; then
        # Remove collectd,fluentd,opentsdb,kibana,grafana
        local newbinlist=
        for bin in ${binlist[@]}
        do
            if [[ ! "${bin}" =~ collectd|fluentd|opentsdb|kibana|grafana|elasticsearch|asynchbase ]]; then
                newbinlist=$newbinlist"$bin "
            fi
        done
        [ -n "$GLB_MAPR_PATCH" ] && [ -z "$(echo $newbinlist | grep mapr-patch)" ] && newbinlist=$newbinlist"mapr-patch"
        echo $newbinlist
    fi
}

## @param path to config
function maprutil_getZKNodes() {
    if [ -z "$1" ]; then
        return 1
    fi
    
    local zknodes=$(grep zoo $1 | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ ! -z "$zknodes" ]; then
        echo $zknodes
    fi
}

## @param path to config
## @param host ip
function maprutil_isClientNode() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    
    local isclient=$(grep $2 $1 | grep 'mapr-client\|mapr-loopbacknfs' | awk -F, '{print $1}' |sed ':a;N;$!ba;s/\n/ /g')
    if [ -n "$isclient" ]; then
        echo $isclient
    fi
}

# @param ip_address_string
# @param cldb host ip
function maprutil_isClusterNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    fi
    local hostip=$(util_getHostIP)
    local mcldb=$2
    local retval=
    if [ "$hostip" = "$1" ]; then
        retval=$(grep $mcldb /opt/mapr/conf/mapr-clusters.conf)
    else
        retval=$(ssh_executeCommand "root" "$1" "grep $mcldb /opt/mapr/conf/mapr-clusters.conf")
        #echo "ssh return value $?"
    fi
    echo $retval
}

# @param full_path_roles_file
function maprutil_getNodesFromRole() {
    if [ -z "$1" ]; then
        return
    fi
    local nodes=
    for i in $(cat $1 | grep '^[^#;]'); do
        local node=$(echo $i | cut -f1 -d",")
        local isvalid=$(util_validip2 $node)
        if [ "$isvalid" = "valid" ]; then
            nodes=$nodes$node" "
        else
            echo "Invalid IP [$node]. Scooting"
            exit 1
        fi
    done
    echo $nodes | tr ' ' '\n' | sort | tr '\n' ' '
}

function maprutil_coresdirs(){
    local dirlist=()
    dirlist+=("/opt/cores/guts*")
    dirlist+=("/opt/cores/mfs*")
    dirlist+=("/opt/cores/java.core.*")
    dirlist+=("/opt/cores/*mrconfig*")
    echo ${dirlist[*]}
}

function maprutil_knowndirs(){
    local dirlist=()
    dirlist+=("/maprdev/")
    dirlist+=("/opt/mapr")
    dirlist+=("/var/mapr-zookeeper-data")
    echo ${dirlist[*]}
}

function maprutil_tempdirs() {
    local dirslist=()
    dirlist+=("/tmp/*mapr*.*")
    dirlist+=("/tmp/hsperfdata*")
    dirlist+=("/tmp/hadoop*")
    dirlist+=("/tmp/*mapr-disk.rules*")
    dirlist+=("/tmp/*.lck")
    dirlist+=("/tmp/mfs*")
    dirlist+=("/tmp/isinstalled_*")
    dirlist+=("/tmp/uninstallnode_*")
    dirlist+=("/tmp/installbinnode_*")
    dirlist+=("/tmp/upgradenode_*")
    dirlist+=("/tmp/disklist*")
    dirlist+=("/tmp/configurenode_*")
    dirlist+=("/tmp/postconfigurenode_*")
    dirlist+=("/tmp/cmdonnode_*")
    dirlist+=("/tmp/defdisks*")
    dirlist+=("/tmp/zipdironnode_*")
    dirlist+=("/tmp/maprbuilds*")
    dirlist+=("/tmp/restartonnode_*")
    dirlist+=("/tmp/maprsetup_*")

    echo  ${dirlist[*]}
}  

function maprutil_removedirs(){
    if [ -z "$1" ]; then
        return
    fi

   case $1 in
        all)
            rm -rfv $(maprutil_knowndirs) > /dev/null 2>&1
            rm -rfv $(maprutil_tempdirs)  > /dev/null 2>&1
            rm -rfv $(maprutil_coresdirs) > /dev/null 2>&1
           ;;
         known)
            rm -rfv $(maprutil_knowndirs) 
           ;;
         temp)
            rm -rfv $(maprutil_tempdirs)
           ;;
         cores)
            rm -rfv $(maprutil_coresdirs)
           ;;
        *)
            log_warn "unknown parameter passed to removedirs \"$PARAM\""
            ;;
    esac
       
}

# @param host ip
function maprutil_isMapRInstalledOnNode(){
    if [ -z "$1" ] ; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/isinstalled_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    echo "util_getInstalledBinaries 'mapr-'" >> $scriptpath

    local bins=
    local hostip=$(util_getHostIP)
    if [ "$hostip" != "$1" ]; then
        bins=$(ssh_executeScriptasRoot "$1" "$scriptpath")
    else
        bins=$(util_getInstalledBinaries "mapr-")
    fi

    if [ -z "$bins" ]; then
        echo "false"
    else
        echo "true"
    fi
}

function maprutil_isMapRInstalledOnNodes(){
    if [ -z "$1" ] ; then
        return
    fi
    local maprnodes=$1
    local tmpdir="$RUNTEMPDIR/installed"
    mkdir -p $tmpdir 2>/dev/null
    local yeslist=
    for node in ${maprnodes[@]}
    do
        local nodelog="$tmpdir/$node.log"
        maprutil_isMapRInstalledOnNode "$node" > $nodelog &
        maprutil_addToPIDList "$!"
    done
    maprutil_wait > /dev/null 2>&1
    for node in ${maprnodes[@]}
    do
        local nodelog=$(cat $tmpdir/$node.log)
        if [ "$nodelog" = "true" ]; then
            yeslist=$yeslist"$node"" "
        fi
    done
    echo "$yeslist"
}

# @param host ip
function maprutil_getMapRVersionOnNode(){
    if [ -z "$1" ] ; then
        return
    fi
    local node=$1
    local version=$(ssh_executeCommandasRoot "$node" "[ -e '/opt/mapr/MapRBuildVersion' ] && cat /opt/mapr/MapRBuildVersion")
    local patch=
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        patch=$(ssh_executeCommandasRoot "$node" "rpm -qa | grep mapr-patch | cut -d'-' -f4 | cut -d'.' -f1")
    elif [ "$nodeos" = "ubuntu" ]; then
        patch=$(ssh_executeCommandasRoot "$node" "dpkg -l | grep mapr-patch | awk '{print $3}' | cut -d'-' -f4 | cut -d'.' -f1")
    fi
    [ -n "$patch" ] && patch=" (patch ${patch})"
    if [ -n "$version" ]; then
        echo $version$patch
    fi
}

function maprutil_unmountNFS(){
    local nfslist=$(mount | grep nfs | grep mapr | grep -v '10.10.10.20' | cut -d' ' -f3)
    for i in $nfslist
    do
        timeout 20 umount -l $i
    done
}

# @param host ip
function maprutil_cleanPrevClusterConfigOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local client=$(maprutil_isClientNode "$2" "$hostnode")
    local scriptpath="$RUNTEMPDIR/cleanupnode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$hostnode"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi
    
    
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    echo "maprutil_cleanPrevClusterConfig" >> $scriptpath
    if [ -n "$client" ]; then
         echo "ISCLIENT=1" >> $scriptpath
    else
        echo "ISCLIENT=0" >> $scriptpath
    fi
    
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
}

function maprutil_cleanPrevClusterConfig(){
    # Kill running traces 
    maprutil_killTraces

    # Unmount NFS
    maprutil_unmountNFS

    # Stop warden
    if [[ "$ISCLIENT" -eq 0 ]]; then
        maprutil_restartWarden "stop" 2>/dev/null
    fi

    # Remove mapr shared memory segments
    util_removeSHMSegments "mapr"

    # kill all processes
    util_kill "initaudit.sh"
    util_kill "pullcentralconfig"
    util_kill "java" "jenkins" "QuorumPeerMain"
    util_kill "FsShell"
    util_kill "CentralConfigCopyHelper"
    
    maprutil_killTraces

    rm -rf /opt/mapr/conf/disktab /opt/mapr/conf/mapr-clusters.conf /opt/mapr/logs/* 2>/dev/null
    
     # Remove all directories
    maprutil_removedirs "cores" > /dev/null 2>&1
    maprutil_removedirs "temp" > /dev/null 2>&1

    if [ -e "/opt/mapr/roles/zookeeper" ]; then
        for i in datacenter services services_config servers ; do 
            /opt/mapr/zookeeper/zookeeper-*/bin/zkCli.sh -server localhost:5181 rmr /$i > /dev/null 2>&1
        done
         # Stop zookeeper
        service mapr-zookeeper stop  2>/dev/null
        util_kill "java" "jenkins" 
    fi
}

function maprutil_uninstall(){
    
    # Kill running traces 
    util_kill "timeout"
    util_kill "guts"
    util_kill "dstat"
    util_kill "iostat"
    util_kill "top -b"
    util_kill "runTraces"
    
    # Unmount NFS
    maprutil_unmountNFS

    # Stop warden
    maprutil_restartWarden "stop"

    # Stop zookeeper
    service mapr-zookeeper stop  2>/dev/null

    # Remove MapR Binaries
    maprutil_removemMapRPackages

    # Run Yum clean
    local nodeos=$(getOS $node)
    if [ "$nodeos" = "centos" ]; then
        yum clean all > /dev/null 2>&1
        yum-complete-transaction --cleanup-only > /dev/null 2>&1
    elif [ "$nodeos" = "ubuntu" ]; then
        apt-get install -f -y > /dev/null 2>&1
        apt-get autoremove -y > /dev/null 2>&1
        apt-get update > /dev/null 2>&1
    fi

    # Remove mapr shared memory segments
    util_removeSHMSegments "mapr"

    # kill all processes
    util_kill "initaudit.sh"
    util_kill "mfs"
    util_kill "java" "jenkins" "elasticsearch"
    util_kill "timeout"
    util_kill "guts"
    util_kill "dstat"
    util_kill "iostat"
    util_kill "top -b"

    # Remove all directories
    maprutil_removedirs "all"

    echo 1 > /proc/sys/vm/drop_caches
}

# @param host ip
function maprutil_uninstallNode(){
    if [ -z "$1" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/uninstallnode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    echo "maprutil_uninstall" >> $scriptpath

    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
}

function maprutil_upgrade(){
    local upbins="mapr-cldb mapr-core mapr-core-internal mapr-fileserver mapr-hadoop-core mapr-historyserver mapr-jobtracker mapr-mapreduce1 mapr-mapreduce2 mapr-metrics mapr-nfs mapr-nodemanager mapr-resourcemanager mapr-tasktracker mapr-webserver mapr-zookeeper mapr-zk-internal"
    local buildversion=$1
    
    local removebins="mapr-patch"
    if [ -n "$(util_getInstalledBinaries $removebins)" ]; then
        util_removeBinaries $removebins
    fi

    util_upgradeBinaries "$upbins" "$buildversion" || exit 1
    
    #mv /opt/mapr/conf/warden.conf  /opt/mapr/conf/warden.conf.old
    #cp /opt/mapr/conf.new/warden.conf /opt/mapr/conf/warden.conf
    if [ -e "/opt/mapr/roles/cldb" ]; then
        log_msghead "Transplant any new changes in warden configs to /opt/mapr/conf/warden.conf. Do so manually!"
        diff /opt/mapr/conf/warden.conf /opt/mapr/conf.new/warden.conf
        if [ -d "/opt/mapr/conf/conf.d.new" ]; then
            log_msghead "New configurations from /opt/mapr/conf/conf.d.new aren't merged with existing files. Do so manually!"
        fi
    fi

    /opt/mapr/server/configure.sh -R

    # Start zookeeper if if exists
    service mapr-zookeeper start 2>/dev/null
    
    # Restart services on the node
    maprutil_restartWarden "start" > /dev/null 2>&1
}

# @param host ip
function maprutil_upgradeNode(){
    if [ -z "$1" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/upgradenode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    if [ -n "$GLB_BUILD_VERSION" ]; then
        echo "maprutil_setupLocalRepo" >> $scriptpath
    fi
    echo "maprutil_upgrade \""$GLB_BUILD_VERSION"\" || exit 1" >> $scriptpath

    ssh_executeScriptasRootInBG "$hostnode" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$2" ]; then
        maprutil_wait
    fi
}

# @param cldbnode
function maprutil_postUpgrade(){
    if [ -z "$1" ]; then
        return
    fi
    local node=$1
    ssh_executeCommandasRoot "$node" "timeout 50 maprcli config save -values {mapr.targetversion:\"\$(cat /opt/mapr/MapRBuildVersion)\"}" > /dev/null 2>&1
    ssh_executeCommandasRoot "$node" "timeout 10 maprcli node list -columns hostname,csvc" 
}

# @param host ip
# @param binary list
# @param don't wait
function maprutil_installBinariesOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    
    # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/installbinnode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    maprutil_addGlobalVars "$scriptpath"
    if [ -n "$GLB_BUILD_VERSION" ]; then
        echo "maprutil_setupLocalRepo" >> $scriptpath
    fi
    echo "keyexists=\$(util_fileExists \"/root/.ssh/id_rsa\")" >> $scriptpath
    echo "[ -z \"\$keyexists\" ] && ssh_createkey \"/root/.ssh\"" >> $scriptpath
    echo "util_installprereq" >> $scriptpath
    local bins="$2"
    local maprpatch=$(echo "$bins" | tr ' ' '\n' | grep mapr-patch)
    [ -n "$maprpatch" ] && bins=$(echo "$bins" | tr ' ' '\n' | grep -v mapr-patch | tr '\n' ' ')
    echo "util_installBinaries \""$bins"\" \""$GLB_BUILD_VERSION"\"" >> $scriptpath
    ## Append MapR release version as there might be conflicts with mapr-patch-client with regex as 'mapr-patch*$VERSION*'
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        [ -n "$maprpatch" ] && echo "util_installBinaries \""$maprpatch"\" \""$GLB_PATCH_VERSION"\" \""-$GLB_MAPR_VERSION"\" || exit 1" >> $scriptpath
    else
        [ -n "$maprpatch" ] && echo "util_installBinaries \""$maprpatch"\" \""$GLB_PATCH_VERSION"\" \""$GLB_MAPR_VERSION"\" || exit 1" >> $scriptpath
    fi
    
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$3" ]; then
        maprutil_wait
    fi
}

function maprutil_configureMultiMFS(){
     if [ -z "$1" ]; then
        return
    fi
    local nummfs=$1
    local numspspermfs=1
    local numsps=$2
    if [ -n "$numsps" ]; then
        numspspermfs=$(echo "$numsps/$nummfs"|bc)
    fi
    local failcnt=2;
    local iter=0;
    while [ "$failcnt" -gt 0 ] && [ "$iter" -lt 5 ]; do
        failcnt=0;
        maprcli  config save -values {multimfs.numinstances.pernode:${nummfs}}
        let failcnt=$failcnt+`echo $?`
        maprcli  config save -values {multimfs.numsps.perinstance:${numspspermfs}}
        let failcnt=$failcnt+`echo $?`
        sleep 30;
        let iter=$iter+1;
    done
}

function maprutil_configurePontis(){
    if [ ! -e "/opt/mapr/conf/mfs.conf" ]; then
        return
    fi
    sed -i 's|mfs.cache.lru.sizes=|#mfs.cache.lru.sizes=|g' /opt/mapr/conf/mfs.conf
    # Adding Specific Cache Settings
    cat >> /opt/mapr/conf/mfs.conf << EOL
#[PONTIS]
mfs.cache.lru.sizes=inode:3:log:3:dir:3:meta:3:small:5:db:5:valc:1
EOL
}

# @param filename
# @param table namespace 
function maprutil_addTableNS(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local filelist=$(find /opt/mapr/ -name $1 -type f ! -path "*/templates/*")
    local tablens=$2
    for i in $filelist; do
        local present=$(cat $i | grep "hbase.table.namespace.mappings")
        if [ -n "$present" ]; then
            continue;
        fi
        sed -i '/<\/configuration>/d' $i
        cat >> $i << EOL
    <!-- MapRDB -->
    <property>
        <name>hbase.table.namespace.mappings</name>
        <value>*:${tablens}</value>
    </property>
</configuration>
EOL
    done
}

# @param filename
function maprutil_addFSThreads(){
    if [ -z "$1" ]; then
        return
    fi
    local filelist=$(find /opt/mapr/ -name $1 -type f ! -path "*/templates/*")
    for i in $filelist; do
        local present=$(cat $i | grep "fs.mapr.threads")
        if [ -n "$present" ]; then
            continue;
        fi
        sed -i '/<\/configuration>/d' $i
        cat >> $i << EOL
    <!-- MapRDB -->
    <property>
        <name>fs.mapr.threads</name>
        <value>64</value>
    </property>
</configuration>
EOL
    done
}

# @param filename
function maprutil_addTabletLRU(){
    if [ -z "$1" ]; then
        return
    fi
    local filelist=$(find /opt/mapr/ -name $1 -type f ! -path "*/templates/*")
    for i in $filelist; do
        local present=$(cat $i | grep "fs.mapr.tabletlru.size.kb")
        if [ -n "$present" ]; then
            continue;
        fi
        sed -i '/<\/configuration>/d' $i
        cat >> $i << EOL
    <!-- MapRDB Client Tablet Cache Size -->
    <property>
        <name>fs.mapr.tabletlru.size.kb</name>
        <value>2000</value>
    </property>
</configuration>
EOL
    done
}

# @param filename
function maprutil_addPutBufferThreshold(){
    if [ -z "$1" ] && [ -z "$2" ]; then
        return
    fi
    local filelist=$(find /opt/mapr/ -name $1 -type f ! -path "*/templates/*")
    local value=$2
    for i in $filelist; do
        local present=$(cat $i | grep "db.mapr.putbuffer.threshold.mb")
        if [ -n "$present" ]; then
            continue;
        fi
        sed -i '/<\/configuration>/d' $i
        cat >> $i << EOL
    <!-- MapRDB Client Put Buffer Threshold Size -->
    <property>
        <name>db.mapr.putbuffer.threshold.mb</name>
        <value>${value}</value>
    </property>
</configuration>
EOL
    done
}

function maprutil_addRootUserToCntrExec(){

    local execfile="container-executor.cfg"
    local execfilelist=$(find /opt/mapr/hadoop -name $execfile -type f ! -path "*/templates/*")
    for i in $execfilelist; do
        local present=$(cat $i | grep "allowed.system.users" | grep -v root)
        if [ -n "$present" ]; then
            sed -i '/^allowed.system.users/ s/$/,root/' $i
        fi
    done
}

function maprutil_customConfigure(){

    local tablens=$GLB_TABLE_NS
    if [ -n "$tablens" ]; then
        maprutil_addTableNS "core-site.xml" "$tablens"
        maprutil_addTableNS "hbase-site.xml" "$tablens"
    fi

    local pontis=$GLB_PONTIS
    if [ -n "$pontis" ]; then
        maprutil_configurePontis
    fi 

    maprutil_addFSThreads "core-site.xml"
    maprutil_addTabletLRU "core-site.xml"
     local putbuffer=$GLB_PUT_BUFFER
    if [ -n "$putbuffer" ]; then
        maprutil_addPutBufferThreshold "core-site.xml" "$putbuffer"
    fi
}

# @param force move CLDB topology
function maprutil_configureCLDBTopology(){
    
    local datatopo=$(maprcli node list -json | grep racktopo | grep "/data/" | wc -l)
    local numdnodes=$(maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | wc -l) 
    local j=0
    while [ "$numdnodes" -ne "$GLB_CLUSTER_SIZE" ] && [ -z "$1" ]; do
        sleep 5
        numdnodes=$(maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | wc -l) 
        let j=j+1
        if [ "$j" -gt 12 ]; then
            break
        fi
    done
    let numdnodes=numdnodes-1

    if [ "$datatopo" -eq "$numdnodes" ]; then
        return
    fi
    #local clustersize=$(maprcli node list -json | grep 'id'| wc -l)
    local clustersize=$GLB_CLUSTER_SIZE
    if [ "$clustersize" -gt 5 ] || [ -n "$1" ]; then
        ## Move all nodes under /data topology
        local datanodes=$(maprcli node list  -json | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | tr "\n" ",")
        maprcli node move -serverids "$datanodes" -topology /data 2>/dev/null
        ### Moving CLDB Nodes to CLDB topology
        #local cldbnode=`maprcli node cldbmaster | grep ServerID | awk {'print $2'}`
        local cldbnodes=$(maprcli node list -json | grep -e configuredservice -e id | grep -B1 cldb | grep id | sed 's/:/ /' | sed 's/\"/ /g' | awk '{print $2}' | tr "\n" "," | sed 's/\,$//')
        maprcli node move -serverids "$cldbnodes" -topology /cldb 2>/dev/null
        ### Moving CLDB Volume as well
        maprcli volume move -name mapr.cldb.internal -topology /cldb 2>/dev/null
    fi
}

function maprutil_moveTSDBVolumeToCLDBTopology(){
    local tsdbexists=$(maprcli volume info -path /mapr.monitoring -json | grep ERROR)
    local cldbtopo=$(maprcli node topo -path /cldb)
    if [ -n "$tsdbexists" ] || [ -z "$cldbtopo" ]; then
        log_warn "OpenTSDB not installed or CLDB not moved to /cldb topology"
        return
    fi

    maprcli volume modify -name mapr.monitoring -minreplication 1 2>/dev/null
    maprcli volume modify -name mapr.monitoring -replication 1 2>/dev/null
    maprcli volume move -name mapr.monitoring -topology /cldb 2>/dev/null
}

# @param diskfile
# @param disk limit
function maprutil_buildDiskList() {
    if [ -z "$1" ]; then
        return
    fi
    local diskfile=$1
    echo "$(util_getRawDisks)" > $diskfile

    local limit=$GLB_MAX_DISKS
    local numdisks=$(wc -l $diskfile | cut -f1 -d' ')
    if [ -n "$limit" ] && [ "$numdisks" -gt "$limit" ]; then
         local newlist=$(head -n $limit $diskfile)
         echo "$newlist" > $diskfile
    fi
}

function maprutil_startTraces() {
    if [[ "$ISCLIENT" -eq "0" ]] && [[ -e "/opt/mapr/roles" ]]; then
        nohup sh -c 'log="/opt/mapr/logs/guts.log"; ec=124; while [ "$ec" -eq 124 ]; do timeout 14 /opt/mapr/bin/guts time:all flush:line cache:all db:all rpc:all log:all dbrepl:all >> $log; ec=$?; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done'  > /dev/null 2>&1 &
        nohup sh -c 'log="/opt/mapr/logs/dstat.log"; ec=124; while [ "$ec" -eq 124 ]; do timeout 14 dstat -tcdnim >> $log; ec=$?; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 10240 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup sh -c 'log="/opt/mapr/logs/iostat.log"; ec=124; while [ "$ec" -eq 124 ]; do timeout 14 iostat -dmxt 1 >> $log 2> /dev/null; ec=$?; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
        nohup sh -c 'log="/opt/mapr/logs/mfstop.log"; rc=0; while [[ "$rc" -ne 137 && -e "/opt/mapr/roles/fileserver" ]]; do mfspid=`pidof mfs`; if [ -n "$mfspid" ]; then timeout 10 top -bH -p $mfspid -d 1 >> $log; rc=$?; else sleep 10; fi; sz=$(stat -c %s $log); [ "$sz" -gt "209715200" ] && tail -c 1048576 $log > $log.bkp && rm -rf $log && mv $log.bkp $log; done' > /dev/null 2>&1 &
    fi
}

function maprutil_killTraces() {
    util_kill "timeout"
    util_kill "guts"
    util_kill "dstat"
    util_kill "iostat"
    util_kill "top -b"
    util_kill "runTraces"
}

function maprutil_configureSSH(){
    if [ -z "$1" ]; then
        return
    fi
    local nodes="$1"
    local hostip=$(util_getHostIP)

    if [ -n $(ssh_checkSSHonNodes "$nodes") ]; then
        for node in ${nodes[@]}
        do
            local isEnabled=$(ssh_check "root" "$node")
            if [ "$isEnabled" != "enabled" ]; then
                log_info "Configuring key-based authentication from $hostip to $node "
                ssh_copyPublicKey "root" "$node"
            fi
        done
    fi
}

function maprutil_configure(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi

    if [ ! -d "/opt/mapr/" ]; then
        >&2 echo "{WARN} Configuration skipped as no MapR binaries are installed "
        return 1
    fi
    
    local diskfile="/tmp/disklist"
    local hostip=$(util_getHostIP)
    local cldbnodes=$(util_getCommaSeparated "$1")
    local cldbnode=$(util_getFirstElement "$1")
    local zknodes=$(util_getCommaSeparated "$2")
    maprutil_buildDiskList "$diskfile"

    if [ "$hostip" != "$cldbnode" ] && [ "$(ssh_check root $cldbnode)" != "enabled" ]; then
        ssh_copyPublicKey "root" "$cldbnode"
    fi

    local extops=
    if [ -n "$GLB_SECURE_CLUSTER" ]; then
        extops="-secure"
        pushd /opt/mapr/conf/ > /dev/null 2>&1
        rm -rf cldb.key ssl_truststore ssl_keystore cldb.key maprserverticket /tmp/maprticket_* > /dev/null 2>&1
        popd > /dev/null 2>&1
        if [ "$hostip" = "$cldbnode" ]; then
            extops=$extops" -genkeys"
        else
            maprutil_copySecureFilesFromCLDB "$cldbnode" "$cldbnodes" "$zknodes"
        fi
    fi

    if [ "$ISCLIENT" -eq 1 ]; then
        log_info "[$hostip] /opt/mapr/server/configure.sh -c -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3 $extops"
        /opt/mapr/server/configure.sh -c -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3 $extops
    else
        log_info "[$hostip] /opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3 $extops"
        /opt/mapr/server/configure.sh -C ${cldbnodes} -Z ${zknodes} -L /opt/mapr/logs/install_config.log -N $3 $extops
    fi
    
    # Perform series of custom configuration based on selected options
    maprutil_customConfigure

    # Return if configuring client node after this
    if [ "$ISCLIENT" -eq 1 ]; then
        log_info "[$hostip] Done configuring client node"
        return 
    fi

    [ -n "$GLB_TRIM_SSD" ] && log_info "[$hostip] Trimming the SSD disks if present..." && util_trimSSDDrives "$(cat $diskfile)"
    
    #echo "/opt/mapr/server/disksetup -FM /tmp/disklist"
    local multimfs=$GLB_MULTI_MFS
    local numsps=$GLB_NUM_SP
    local numdisks=`wc -l $diskfile | cut -f1 -d' '`
    if [ -n "$multimfs" ] && [ "$multimfs" -gt 1 ]; then
        if [ "$multimfs" -gt "$numdisks" ]; then
            log_info "Node ["`hostname -s`"] has fewer disks than mfs instances. Defaulting # of mfs to # of disks"
            multimfs=$numdisks
        fi
        local numstripe=$(echo $numdisks/$multimfs|bc)
        if [ -n "$numsps" ] && [ "$numsps" -le "$numdisks" ]; then
            numstripe=$(echo "$numdisks/$numsps"|bc)
        else
            numsps=
        fi
        /opt/mapr/server/disksetup -FW $numstripe $diskfile
    elif [[ -n "$numsps" ]] &&  [[ "$numsps" -le "$numdisks" ]]; then
        if [ $((numdisks%2)) -eq 1 ] && [ $((numsps%2)) -eq 0 ]; then
            numdisks=$(echo "$numdisks+1" | bc)
        fi
        local numstripe=$(echo "$numdisks/$numsps"|bc)
        /opt/mapr/server/disksetup -FW $numstripe $diskfile
    else
        /opt/mapr/server/disksetup -FM $diskfile
    fi

    # Add root user to container-executor.cfg
    maprutil_addRootUserToCntrExec

    # Start zookeeper
    service mapr-zookeeper start 2>/dev/null
    
    # Restart services on the node
    maprutil_restartWarden > /dev/null 2>&1

   if [ "$hostip" = "$cldbnode" ]; then
        maprutil_mountSelfHosting
        maprutil_applyLicense
        if [ -n "$multimfs" ] && [ "$multimfs" -gt 1 ]; then
            maprutil_configureMultiMFS "$multimfs" "$numsps"
        fi
        local cldbtopo=$GLB_CLDB_TOPO
        if [ -n "$cldbtopo" ]; then
            sleep 30
            maprutil_configureCLDBTopology || exit 1
        fi
    else
        [ -n "$GLB_SECURE_CLUSTER" ] &&  maprutil_copyMapRTicketsFromCLDB "$cldbnode"
    fi

    if [ -n "$GLB_TRACE_ON" ]; then
        maprutil_startTraces
    fi
}

# @param host ip
# @param config file path
# @param cluster name
# @param don't wait
function maprutil_configureNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
     # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/configurenode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local hostip=$(util_getHostIP)
    local allnodes=$(maprutil_getNodesFromRole "$2")
    local cldbnodes=$(maprutil_getCLDBNodes "$2")
    local cldbnode=$(util_getFirstElement "$cldbnodes")
    local zknodes=$(maprutil_getZKNodes "$2")
    local client=$(maprutil_isClientNode "$2" "$hostnode")
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath

    maprutil_addGlobalVars "$scriptpath"
    if [ -n "$client" ]; then
         echo "ISCLIENT=1" >> $scriptpath
    else
        echo "ISCLIENT=0" >> $scriptpath
    fi
    
    if [ "$hostip" != "$cldbnode" ] && [ "$hostnode" = "$cldbnode" ]; then
        echo "maprutil_configureSSH \""$allnodes"\" && maprutil_configure \""$cldbnodes"\" \""$zknodes"\" \""$3"\" || exit 1" >> $scriptpath
    else
        echo "maprutil_configure \""$cldbnodes"\" \""$zknodes"\" \""$3"\" || exit 1" >> $scriptpath
    fi
   
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$4" ]; then
        maprutil_wait
    fi
}

function maprutil_postConfigure(){
    if [ -z "$1" ] && [ -z "$2" ]; then
        return
    fi
    local esnodes=$(util_getCommaSeparated "$1")
    local otnodes=$(util_getCommaSeparated "$2")
    
    local cmd="/opt/mapr/server/configure.sh "
    if [ -n "$esnodes" ]; then
        cmd=$cmd" -ES "$esnodes
    fi
    if [ -n "$otnodes" ]; then
        cmd=$cmd" -OT "$otnodes
    fi
    cmd=$cmd" -R"

    log_info "$cmd"
    bash -c "$cmd"

    #maprutil_restartWarden
}

# @param cldbnode ip
function maprutil_copyMapRTicketsFromCLDB(){
    if [ -z "$1" ]; then
        return
    fi
    local cldbhost=$1
    
    # Check if CLDB is configured & files are available for copy
    local cldbisup="false"
    local i=0
    while [ "$cldbisup" = "false" ]; do
        cldbisup=$(ssh_executeCommandasRoot "$cldbhost" "[ -e '/tmp/maprticket_0' ] && echo true || echo false")
        if [ "$cldbisup" = "false" ]; then
            sleep 10
        else
            cldbisup="true"
            sleep 10
            break
        fi
        let i=i+1
        if [ "$i" -gt 18 ]; then
            log_warn "[$(util_getHostIP)] Timed out waiting to find 'maprticket_0' on CLDB node [$cldbhost]. Copy manually!"
            break
        fi
    done
    
    if [ "$cldbisup" = "true" ] && [ "$ISCLIENT" -eq 0 ]; then
        ssh_copyFromCommandinBG "root" "$cldbhost" "/tmp/maprticket_*" "/tmp" 2>/dev/null
    fi
}

# @param cldbnode ip
function maprutil_copySecureFilesFromCLDB(){
    local cldbhost=$1
    local cldbnodes=$2
    local zknodes=$3
    
    # Check if CLDB is configured & files are available for copy
    local cldbisup="false"
    local i=0
    while [ "$cldbisup" = "false" ]; do
        cldbisup=$(ssh_executeCommandasRoot "$cldbhost" "[ -e '/opt/mapr/conf/cldb.key' ] && [ -e '/opt/mapr/conf/maprserverticket' ] && [ -e '/opt/mapr/conf/ssl_keystore' ] && [ -e '/opt/mapr/conf/ssl_truststore' ] && echo true || echo false")
        if [ "$cldbisup" = "false" ]; then
            sleep 10
        else
            break
        fi
        let i=i+1
        if [ "$i" -gt 18 ]; then
            log_warn "[$(util_getHostIP)] Timed out waiting to find cldb.key on CLDB node [$cldbhost]. Exiting!"
            exit 1
        fi
    done
    
    sleep 10

    if [[ -n "$(echo $cldbnodes | grep $hostip)" ]] || [[ -n "$(echo $zknodes | grep $hostip)" ]]; then
        ssh_copyFromCommandinBG "root" "$cldbhost" "/opt/mapr/conf/cldb.key" "/opt/mapr/conf/"; maprutil_addToPIDList "$!" 
    fi
    if [ "$ISCLIENT" -eq 0 ]; then
        ssh_copyFromCommandinBG "root" "$cldbhost" "/opt/mapr/conf/ssl_keystore" "/opt/mapr/conf/"; maprutil_addToPIDList "$!" 
        ssh_copyFromCommandinBG "root" "$cldbhost" "/opt/mapr/conf/maprserverticket" "/opt/mapr/conf/"; maprutil_addToPIDList "$!" 
    fi
    ssh_copyFromCommandinBG "root" "$cldbhost" "/opt/mapr/conf/ssl_truststore" "/opt/mapr/conf/"; maprutil_addToPIDList "$!" 
    
    maprutil_wait

    if [ "$ISCLIENT" -eq 0 ]; then
        chown mapr:mapr /opt/mapr/conf/maprserverticket > /dev/null 2>&1
        chmod +600 /opt/mapr/conf/maprserverticket /opt/mapr/conf/ssl_keystore > /dev/null 2>&1
    fi
    chmod +444 /opt/mapr/conf/ssl_truststore > /dev/null 2>&1
}
# @param host ip
# @param config file path
# @param cluster name
# @param don't wait
function maprutil_postConfigureOnNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
     # build full script for node
    local hostnode=$1
    local scriptpath="$RUNTEMPDIR/postconfigurenode_${hostnode: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$1"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local esnodes=$(maprutil_getESNodes "$2")
    local otnodes=$(maprutil_getOTSDBNodes "$2")
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath

    maprutil_addGlobalVars "$scriptpath"
    
    echo "maprutil_postConfigure \""$esnodes"\" \""$otnodes"\" || exit 1" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$1" "$scriptpath"
    maprutil_addToPIDList "$!"
    if [ -z "$3" ]; then
        maprutil_wait
    fi
}

# @param script path
function maprutil_addGlobalVars(){
    if [ -z "$1" ]; then
        return
    fi
    local scriptpath=$1
    local glbvars=$( set -o posix ; set  | grep GLB_)
    for i in $glbvars
    do
        #echo "%%%%%%%%%% -> $i <- %%%%%%%%%%%%%"
        if [[ "$i" =~ ^GLB_BG_PIDS.* ]]; then
            continue
        elif [[ ! "$i" =~ ^GLB_.* ]]; then
            continue
        fi
        echo $i >> $scriptpath
    done
}

function maprutil_getBuildID(){
    local buildid=$(cat /opt/mapr/MapRBuildVersion)
    echo "$buildid"
}

# @param node
# @param build id
function maprutil_checkBuildExists(){
     if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local node=$1
    local buildid=$2
    local retval=
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        retval=$(ssh_executeCommandasRoot "$node" "yum --showduplicates list mapr-core | grep $buildid")
    elif [ "$nodeos" = "ubuntu" ]; then
        retval=$(ssh_executeCommandasRoot "$node" "apt-get update >/dev/null 2>&1 && apt-cache policy mapr-core | grep $buildid")
    fi
    echo "$retval"
}

# @param node
function maprutil_checkNewBuildExists(){
    if [ -z "$1" ]; then
        return
    fi
    local node=$1
    local buildid=$(maprutil_getMapRVersionOnNode $node)
    local curchangeset=$(echo $buildid | cut -d'.' -f4)
    local newchangeset=
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        #ssh_executeCommandasRoot "$node" "yum clean all" > /dev/null 2>&1
        newchangeset=$(ssh_executeCommandasRoot "$node" "yum clean all > /dev/null 2>&1; yum --showduplicates list mapr-core | grep -v '$curchangeset' | tail -n1 | awk '{print \$2}' | cut -d'.' -f4")
    elif [ "$nodeos" = "ubuntu" ]; then
        newchangeset=$(ssh_executeCommandasRoot "$node" "apt-get update > /dev/null 2>&1; apt-cache policy mapr-core | grep Candidate | grep -v '$curchangeset' | awk '{print \$2}' | cut -d'.' -f4")
    fi

    if [[ -n "$newchangeset" ]] && [[ "$(util_isNumber $newchangeset)" = "true" ]] && [[ "$newchangeset" -gt "$curchangeset" ]]; then
        echo "$newchangeset"
    fi
}

function maprutil_getMapRVersionFromRepo(){
    if [ -z "$1" ]; then
        return
    fi
    local node=$1
    local nodeos=$(getOSFromNode $node)
    local maprversion=
    if [ "$nodeos" = "centos" ]; then
        #ssh_executeCommandasRoot "$node" "yum clean all" > /dev/null 2>&1
        maprversion=$(ssh_executeCommandasRoot "$node" "yum --showduplicates list mapr-core 2> /dev/null | grep mapr-core | tail -n1 | awk '{print \$2}' | cut -d'.' -f1-3")
    elif [ "$nodeos" = "ubuntu" ]; then
        maprversion=$(ssh_executeCommandasRoot "$node" "apt-cache policy mapr-core 2> /dev/null | grep Candidate | awk '{print \$2}' | cut -d'.' -f1-3")
    fi

    if [[ -n "$maprversion" ]]; then
        echo "$maprversion"
    fi
}

function maprutil_copyRepoFile(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local node=$1
    local repofile=$2
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        ssh_executeCommandasRoot "$1" "sed -i 's/^enabled.*/enabled = 0/g' /etc/yum.repos.d/*mapr*.repo > /dev/null 2>&1"
        ssh_copyCommandasRoot "$node" "$2" "/etc/yum.repos.d/"
    elif [ "$nodeos" = "ubuntu" ]; then
        ssh_executeCommandasRoot "$1" "rm -rf /etc/apt/sources.list.d/*mapr*.list > /dev/null 2>&1"
        ssh_executeCommandasRoot "$1" "sed -i '/apt.qa.lab/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1"
        ssh_executeCommandasRoot "$1" "sed -i '/artifactory.devops.lab/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1"
        ssh_executeCommandasRoot "$1" "sed -i '/package.mapr.com/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1"

        ssh_copyCommandasRoot "$node" "$2" "/etc/apt/sources.list.d/"
    fi
}

function maprutil_buildRepoFile(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
    local repofile=$1
    local repourl=$2
    local node=$3
    local nodeos=$(getOSFromNode $node)
    if [ "$nodeos" = "centos" ]; then
        echo "[QA-CustomOpensource]" > $repofile
        echo "name=MapR Latest Build QA Repository" >> $repofile
        echo "baseurl=http://yum.qa.lab/opensource" >> $repofile
        echo "enabled=1" >> $repofile
        echo "gpgcheck=0" >> $repofile
        echo "protect=1" >> $repofile
        echo >> $repofile
        echo "[QA-CustomRepo]" >> $repofile
        echo "name=MapR Custom Repository" >> $repofile
        echo "baseurl=${repourl}" >> $repofile
        echo "enabled=1" >> $repofile
        echo "gpgcheck=0" >> $repofile
        echo "protect=1" >> $repofile

        # Add patch if specified
        if [ -n "$GLB_PATCH_REPOFILE" ] ; then
            echo "[QA-CustomPatchRepo]" >> $repofile
            echo "name=MapR Custom Repository" >> $repofile
            echo "baseurl=${GLB_PATCH_REPOFILE}" >> $repofile
            echo "enabled=1" >> $repofile
            echo "gpgcheck=0" >> $repofile
            echo "protect=1" >> $repofile
        fi
        echo >> $repofile
    elif [ "$nodeos" = "ubuntu" ]; then
        echo "deb http://apt.qa.lab/opensource binary/" > $repofile
        echo "deb ${repourl} binary ubuntu" >> $repofile
        [ -n "$GLB_PATCH_REPOURL" ] && echo "deb ${GLB_PATCH_REPOURL} binary ubuntu" >> $repofile
    fi
}

function maprutil_getRepoURL(){
    local nodeos=$(getOS)
    if [ "$nodeos" = "centos" ]; then
        local repolist=$(yum repolist enabled -v | grep -e Repo-id -e Repo-baseurl -e MapR | grep -A1 -B1 MapR | grep -v Repo-name | grep -iv opensource | grep Repo-baseurl | cut -d':' -f2- | tr -d " " | head -1)
        echo "$repolist"
    elif [ "$nodeos" = "ubuntu" ]; then
        local repolist=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com| awk '{print $2}' | grep -iv opensource | head -1)
        echo "$repolist"
    fi
}

function maprutil_getPatchRepoURL(){
    local nodeos=$(getOS)
    if [ "$nodeos" = "centos" ]; then
        local repolist=$(yum repolist enabled -v | grep -e Repo-id -e Repo-baseurl -e MapR | grep -A1 -B1 MapR | grep -v Repo-name | grep -iv opensource | grep Repo-baseurl | grep EBF | cut -d':' -f2- | tr -d " " | head -1)
        echo "$repolist"
    elif [ "$nodeos" = "ubuntu" ]; then
        local repolist=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com| awk '{print $2}' | grep -iv opensource | head -1)
        echo "$repolist"
    fi
}

function maprutil_disableAllRepo(){
    local nodeos=$(getOS)
    if [ "$nodeos" = "centos" ]; then
        local repolist=$(yum repolist enabled -v | grep -e Repo-id -e Repo-baseurl -e MapR | grep -A1 -B1 MapR | grep -v Repo-name | grep -iv opensource | grep Repo-id | cut -d':' -f2 | tr -d " ")
        for repo in $repolist
        do
            log_info "[$(util_getHostIP)] Disabling repository $repo"
            yum-config-manager --disable $repo > /dev/null 2>&1
        done
    elif [ "$nodeos" = "ubuntu" ]; then
        local repolist=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep -e apt.qa.lab -e artifactory.devops.lab -e package.mapr.com| awk '{print $2}' | grep -iv opensource | cut -d '/' -f3)
        for repo in $repolist
        do
           local repof=$(grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -v ':#' | grep $repo | cut -d":" -f1)
           sed -i "/${repo}/s/^/#/" ${repof}
        done
    fi
}

# @param local repo path
function maprutil_addLocalRepo(){
    if [ -z "$1" ]; then
        return
    fi
    local nodeos=$(getOS)
    local repofile="/tmp/maprbuilds/mapr-$GLB_BUILD_VERSION.repo"
    if [ "$nodeos" = "ubuntu" ]; then
        repofile="/tmp/maprbuilds/mapr-$GLB_BUILD_VERSION.list"
    fi

    local repourl=$1
    log_info "[$(util_getHostIP)] Adding local repo $repourl for installing the binaries"
    if [ "$nodeos" = "centos" ]; then
        echo "[MapR-LocalRepo-$GLB_BUILD_VERSION]" > $repofile
        echo "name=MapR $GLB_BUILD_VERSION Repository" >> $repofile
        echo "baseurl=file://$repourl" >> $repofile
        echo "enabled=1" >> $repofile
        echo "gpgcheck=0" >> $repofile
        echo "protect=1" >> $repofile
        cp $repofile /etc/yum.repos.d/ > /dev/null 2>&1
        yum-config-manager --enable MapR-LocalRepo-$GLB_BUILD_VERSION > /dev/null 2>&1
    elif [ "$nodeos" = "ubuntu" ]; then
        echo "deb file:$repourl ./" > $repofile
        cp $repofile /etc/apt/sources.list.d/ > /dev/null 2>&1
        apt-get update > /dev/null 2>&1
    fi
}

# @param directory to download
# @param url to download
# @param filter keywork
function maprutil_downloadBinaries(){
     if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return
    fi
    local nodeos=$(getOS)
    local dlddir=$1
    mkdir -p $dlddir > /dev/null 2>&1
    local repourl=$2
    local searchkey=$3
    log_info "[$(util_getHostIP)] Downloading binaries for version [$searchkey]"
    if [ "$nodeos" = "centos" ]; then
        pushd $dlddir > /dev/null 2>&1
        wget -r -np -nH -nd --cut-dirs=1 --accept "*${searchkey}*.rpm" ${repourl} > /dev/null 2>&1
        popd > /dev/null 2>&1
        createrepo $dlddir > /dev/null 2>&1
    elif [ "$nodeos" = "ubuntu" ]; then
        pushd $dlddir > /dev/null 2>&1
        wget -r -np -nH -nd --cut-dirs=1 --accept "*${searchkey}*.deb" ${repourl} > /dev/null 2>&1
        dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
        popd > /dev/null 2>&1
    fi
}

function maprutil_setupLocalRepo(){
    local repourl=$(maprutil_getRepoURL)
    local patchrepo=$(maprutil_getPatchRepoURL)
    maprutil_disableAllRepo
    maprutil_downloadBinaries "/tmp/maprbuilds/$GLB_BUILD_VERSION" "$repourl" "$GLB_BUILD_VERSION"
    if [ -n "$patchrepo" ]; then
        local patchkey=
        if [ -z "$GLB_PATCH_VERSION" ]; then
            patchkey=$(lynx -dump -listonly ${patchrepo} | grep mapr-patch-[0-9] | tail -n 1 | awk '{print $2}' | rev | cut -d'/' -f1 | cut -d'.' -f2- | rev)
        else
            patchkey="mapr-patch*$GLB_BUILD_VERSION*$GLB_PATCH_VERSION"
        fi
        maprutil_downloadBinaries "/tmp/maprbuilds/$GLB_BUILD_VERSION" "$patchrepo" "$patchkey"
    fi
    maprutil_addLocalRepo "/tmp/maprbuilds/$GLB_BUILD_VERSION"
}

function maprutil_runCommandsOnNodesInParallel(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi

    local nodes=$1
    local cmd=$2

    local tempdir="$RUNTEMPDIR/cmdrun"
    mkdir -p $tempdir > /dev/null 2>&1
    for node in ${nodes[@]}
    do
        local nodefile="$tempdir/$node.log"
        maprutil_runCommandsOnNode "$node" "$cmd" > $nodefile &
        maprutil_addToPIDList "$!" 
    done
    maprutil_wait > /dev/null 2>&1

    for node in ${nodes[@]}
    do
        cat "$tempdir/$node.log" 2>/dev/null
    done
    rm -rf $tempdir > /dev/null 2>&1
}

# @param host node
# @param ycsb/tablecreate
function maprutil_runCommandsOnNode(){
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    
    local node=$1
    
     # build full script for node
    local scriptpath="$RUNTEMPDIR/cmdonnode_${node: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    local client=$(maprutil_isClientNode "$2" "$hostnode")
    local hostip=$(util_getHostIP)
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    maprutil_addGlobalVars "$scriptpath"
    
    echo "maprutil_runCommands \"$2\"" >> $scriptpath
   
    if [ "$hostip" != "$node" ]; then
        ssh_executeScriptasRoot "$node" "$scriptpath"
    else
        maprutil_runCommands "$2"
    fi
}

# @param command
function maprutil_runMapRCmd(){
    if [ -z "$1" ]; then
        return
    fi
    local cmd=`$1 > /dev/null;echo $?`;
    local i=0
    while [ "${cmd}" -ne "0" ]; do
        sleep 20
        let i=i+1
        if [ "$i" -gt 3 ]; then
            log_warn "Failed to run command [ $1 ]"
           return
        fi
    done
}

function maprutil_runCommands(){
    if [ -z "$1" ]; then
        return
    fi
    for i in $1
    do
        case $i in
            cldbtopo)
                maprutil_configureCLDBTopology "force"
            ;;
            tsdbtopo)
                maprutil_moveTSDBVolumeToCLDBTopology
            ;;
            ycsb)
                maprutil_createYCSBVolume
            ;;
            tablecreate)
                maprutil_createTableWithCompressionOff
            ;;
            jsontable)
                maprutil_createJSONTable
            ;;
            jsontablecf)
                maprutil_createJSONTable
                maprutil_addCFtoJSONTable
            ;;
            tablelz4)
                maprutil_createTableWithCompression
            ;;
            diskcheck)
               maprutil_checkDiskErrors
            ;;
            tabletdist)
                maprutil_checkTabletDistribution
            ;;
            disktest)
                maprutil_runDiskTest
            ;;
            sysinfo)
                maprutil_sysinfo
            ;;
            sysinfo2)
                maprutil_sysinfo "all"
            ;;
            mfsgrep)
                maprutil_grepMFSLogs
            ;;
            grepmapr)
                maprutil_grepMapRLogs
            ;;
            traceon)
                maprutil_killTraces
                maprutil_startTraces
            ;;
            *)
            echo "Nothing to do!!"
            ;;
        esac
    done
}

function maprutil_createYCSBVolume () {
    log_msghead " *************** Creating YCSB Volume **************** "
    maprutil_runMapRCmd "maprcli volume create -name tables -path /tables -replication 3 -topology /data"
    maprutil_runMapRCmd "hadoop mfs -setcompression off /tables"
}

function maprutil_createTableWithCompression(){
    log_msghead " *************** Creating UserTable (/tables/usertable) with lz4 compression **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "maprcli table create -path /tables/usertable" 
    maprutil_runMapRCmd "maprcli table cf create -path /tables/usertable -cfname family -compression lz4 -maxversions 1"
}

function maprutil_createTableWithCompressionOff(){
    log_msghead " *************** Creating UserTable (/tables/usertable) with compression off **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "maprcli table create -path /tables/usertable"
    maprutil_runMapRCmd "maprcli table cf create -path /tables/usertable -cfname family -compression off -maxversions 1"
}

function maprutil_createJSONTable(){
    log_msghead " *************** Creating JSON UserTable (/tables/usertable) with compression off **************** "
    maprutil_createYCSBVolume
    maprutil_runMapRCmd "maprcli table create -path /tables/usertable -tabletype json "
}

function maprutil_addCFtoJSONTable(){
    log_msghead " *************** Creating JSON UserTable (/tables/usertable) with compression off **************** "
    maprutil_runMapRCmd "maprcli table cf create -path /tables/usertable -cfname cfother -jsonpath field0 -compression off -inmemory true"
}

function maprutil_checkDiskErrors(){
    log_msghead " [$(util_getHostIP)] Checking for disk errors "
    local numlines=2
    [ -n "$GLB_LOG_VERBOSE" ] && numlines=all
    util_grepFiles "$numlines" "/opt/mapr/logs/" "mfs.log*" "DHL" "lun.cc"
}

function maprutil_runDiskTest(){
    local maprdisks=$(util_getRawDisks)
    if [ -z "$maprdisks" ]; then
        return
    fi
    echo
    log_msghead "[$(util_getHostIP)] Running disk tests [$maprdisks]"
    local disktestdir="/tmp/disktest"
    mkdir -p $disktestdir 2>/dev/null
    for disk in ${maprdisks[@]}
    do  
        local disklog="$disktestdir/${disk////_}.log"
        hdparm -tT $disk > $disklog &
    done
    wait
    for file in $(find $disktestdir -type f | sort)
    do
        grep -v '^$' $file
    done
    rm -rf $disktestdir 2>/dev/null
}

function maprutil_checkTabletDistribution(){
    if [[ -z "$GLB_TABLET_DIST" ]] || [[ ! -e "/opt/mapr/roles/fileserver" ]]; then
        return
    fi
    
    local filepath=$GLB_TABLET_DIST
    local hostnode=$(hostname -f)

    local cntrlist=$(/opt/mapr/server/mrconfig info dumpcontainers | awk '{print $1, $3}' | sed 's/:\/dev.*//g' | tr ':' ' ' | awk '{print $4,$2}')
    local tabletContainers=$(maprcli table region list -path $filepath -json | grep -v 'secondary' | grep -A10 $hostnode | grep fid | cut -d":" -f2 | cut -d"." -f1 | tr -d '"')
    if [ -z "$tabletContainers" ]; then
        return
    fi
    local storagePools=$(/opt/mapr/server/mrconfig sp list | grep name | cut -d":" -f2 | awk '{print $2}' | tr -d ',' | sort)
    local numTablets=$(echo "$tabletContainers" | wc -l)
    local numContainers=$(echo "$tabletContainers" | sort | uniq | wc -l)
    log_msg "$(util_getHostIP) : [# of tablets: $numTablets], [# of containers: $numContainers]"

    for sp in $storagePools; do
        local spcntrs=$(echo "$cntrlist" | grep $sp | awk '{print $2}')
        local cnt=$(echo "$tabletContainers" |  grep -Fw "${spcntrs}" | wc -l)
        log_msg "\t$sp : $cnt Tablets"
    done
}

function maprutil_sysinfo(){
    echo
    log_msghead "[$(util_getHostIP)] System info"
    
    local options=
    [ -z "$GLB_SYSINFO_OPTION" ] && GLB_SYSINFO_OPTION="all"

    if [ "$(echo $GLB_SYSINFO_OPTION | grep all)" ]; then
        options="all"
    else
        options=$(echo $GLB_SYSINFO_OPTION | tr "," "\n")
    fi

    [ -n "$1" ] && options="all"

    for i in $options
    do
        case $i in
            cpu)
                util_getCPUInfo
            ;;
            disk)
                util_getDiskInfo
            ;;
            nw)
                util_getNetInfo
            ;;
            mem)
                util_getMemInfo
            ;;
            machine)
                util_getMachineInfo
            ;;
            mapr)
                maprutil_getMapRInfo
            ;;
            all)
                maprutil_getMapRInfo
                util_getMachineInfo
                util_getCPUInfo
                util_getMemInfo
                util_getNetInfo
                util_getDiskInfo
            ;;
        esac
    done
}

function maprutil_grepMFSLogs(){
    echo
    log_msghead "[$(util_getHostIP)] Searching MFS logs for FATAL & DHL messages"
    local dirpath="/opt/mapr/logs"
    local fileprefix="mfs.log*"
    local numlines=2
    [ -n "$GLB_LOG_VERBOSE" ] && numlines=all

    util_grepFiles "$numlines" "$dirpath" "$fileprefix" "FATAL"
    util_grepFiles "$numlines" "$dirpath" "$fileprefix" "DHL" "lun.cc"
}

function maprutil_grepMapRLogs(){
    echo
    log_msghead "[$(util_getHostIP)] Searching MapR logs"
    local dirpath="/opt/mapr/logs"
    local fileprefix="*"
    local numlines=2
    [ -n "$GLB_LOG_VERBOSE" ] && numlines=all

    util_grepFiles "$numlines" "$dirpath" "$fileprefix" "$GLB_GREP_MAPRLOGS"
}

function maprutil_getMapRInfo(){
    local version=$(cat /opt/mapr/MapRBuildVersion 2>/dev/null)
    [ -z "$version" ] && return

    local roles=$(ls /opt/mapr/roles 2>/dev/null| tr '\n' ' ')
    local nodeos=$(getOS)
    local patch=
    local client=
    local bins=
    if [ "$nodeos" = "centos" ]; then
        local rpms=$(rpm -qa)
        patch=$(echo "$rpms" | grep mapr-patch | cut -d'-' -f4 | cut -d'.' -f1)
        client=$(echo "$rpms" | grep mapr-client | cut -d'-' -f3)
        bins=$(echo "$rpms" | grep mapr- | sort | cut -d'-' -f1-2 | tr '\n' ' ')
    elif [ "$nodeos" = "ubuntu" ]; then
        local debs=$(dpkg -l)
        patch=$(echo "$debs" | grep mapr-patch | awk '{print $3}' | cut -d'-' -f4 | cut -d'.' -f1)
        client=$(echo "$debs" | grep mapr-client | awk '{print $3}' | cut -d'-' -f1)
        bins=$(echo "$debs" | grep mapr- | awk '{print $2}' | sort | tr '\n' ' ')
    fi
    [ -n "$patch" ] && version="$version (patch ${patch})"
    local nummfs=
    local numsps=
    local sppermfs=
    local nodetopo=
    if [ -e "/opt/mapr/conf/mapr-clusters.conf" ]; then
        nummfs=$(/opt/mapr/server/mrconfig info instances 2>/dev/null| head -1)
        numsps=$(/opt/mapr/server/mrconfig sp list 2>/dev/null| grep SP[0-9] | wc -l)
        command -v maprcli >/dev/null 2>&1 && sppermfs=$(maprcli config load -json 2>/dev/null| grep multimfs.numsps.perinstance | tr -d '"' | tr -d ',' | cut -d':' -f2)
        [[ "$sppermfs" -eq 0 ]] && sppermfs=$numsps
        command -v maprcli >/dev/null 2>&1 && nodetopo=$(maprcli node list -json | grep "$(hostname -f)" | grep racktopo | sed "s/$(hostname -f)//g" | cut -d ':' -f2 | tr -d '"' | tr -d ',')
    fi
    
    log_msghead "MapR Info : "
    [ -n "$roles" ] && log_msg "\t Roles    : $roles"
    log_msg "\t Version  : ${version}"
    [ -n "$client" ] && log_msg "\t Client   : ${client}"
    log_msg "\t Binaries : $bins"
    [[ -n "$nummfs" ]] && [[ "$nummfs" -gt 0 ]] && log_msg "\t # of MFS : $nummfs"
    [[ -n "$numsps" ]] && [[ "$numsps" -gt 0 ]] && log_msg "\t # of SPs : $numsps (${sppermfs} per mfs)"
    [[ -n "$nodetopo" ]] && log_msg "\t Topology : ${nodetopo%?}"
}

function maprutil_getClusterSpec(){
    if [ -z "$1" ]; then
        return
    fi
    local nodelist=$1
    local sysinfo=$(maprutil_runCommandsOnNodesInParallel "$nodelist" "sysinfo2" | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g')
    local hwspec=
    local sysspec=
    local maprspec=

    # Build System Spec

    local numnodes=$(echo "$sysinfo" | grep "System info" | wc -l)
    sysspec="$numnodes nodes"

    ## CPU
    local cpucores=$(echo "$sysinfo" | grep -A1 cores | grep -B1 Enabled | grep cores | cut -d ':' -f2 | sed 's/ *//g')
    [ -n "$cpucores" ] && [ "$(echo $cpucores| wc -w)" -ne "$numnodes" ] && log_warn "CPU hyperthreading mismatch on nodes" && cpucores=0
    [ -n "$cpucores" ] && cpucores=$(echo "$cpucores" | uniq)
    if [ -n "$cpucores" ] && [ "$(echo $cpucores | wc -w)" -gt "1" ]; then
        log_warn "CPU cores do not match. Not a homogeneous cluster"
        cpucores=$(echo "$cpucores" | sort -nr | head -1)
    elif [ -n "$cpucores" ]; then
        cpucores="2 x $cpucores"
    fi
    
    if [ -z "$cpucores" ]; then
        cpucores=$(echo "$sysinfo" | grep -A1 cores | grep -B1 Disabled | grep cores | cut -d ':' -f2 | sed 's/ *//g' | uniq)
        [ -n "$cpucores" ] && [ "$(echo $cpucores | wc -w)" -gt "1" ] && log_warn "CPU cores do not match. Not a homogeneous cluster" && cpucores=$(echo "$cpucores" | sort -nr | head -1)
    fi

    hwspec="$cpucores cores"
    ## Disk
    local numdisks=$(echo "$sysinfo" | grep "Disk Info" | cut -d':' -f3 | tr -d ']' | sed 's/ *//g')
    if [ -n "$numdisks" ]; then 
        [ "$(echo $numdisks| wc -w)" -ne "$numnodes" ] && log_warn "Few nodes do not have disks"
        numdisks=$(echo "$numdisks" | uniq)
        if [ "$(echo $numdisks | wc -w)" -gt "1" ]; then
            log_warn "# of disks do not match. Not a homogeneous cluster"
            numdisks=$(echo "$numdisks" | sort -nr | head -1)
        fi
    else
        log_error "No disks listed on any nodes"
        numdisks=0
    fi
    
    ## More disk info
    local diskstr=$(echo "$sysinfo" | grep -A${numdisks} "Disk Info" | grep -v OS | grep -v USED | grep Type: )
    local diskcnt=$(echo "$diskstr" | sort -k1 | awk '{print $1}' | uniq -c | wc -l)
    if [ "$diskcnt" -ge "$numdisks" ]; then
        diskcnt=$(echo "$diskstr" | sort -k1 | awk '{print $1}' | uniq -c | awk '{print $1}' | uniq -c | sort -nr | head -1 | awk '{print $2}')
    fi
    [ "$diskcnt" -lt "$numdisks" ] && numdisks=$diskcnt
    
    local disktype=$(echo "$diskstr" | awk '{print $4}' | tr -d ',' | uniq)
    if [ "$(echo $disktype | wc -w)" -gt "1" ]; then
        log_warn "Mix of HDD & SSD disks. Not a homogeneous cluster"
        disktype=$(echo "$diskstr" | awk '{print $4}' | tr -d ',' | uniq -c | sort -nr | awk '{print $2}')
    fi

    local disksize=$(echo "$diskstr" | awk '{print $6}' | uniq)
    if [ "$(echo $disksize | wc -w)" -gt "1" ]; then
        local dz=
        for d in $disksize
        do
            local sz=$(util_getNearestPower2 $d)
            [ -z "$dz" ] && dz=$sz
            [ "$sz" -ne "$dz" ] && log_warn "Disks are of different capacities"
        done
        disksize=$(echo "$diskstr" | awk '{print $6}' | uniq | sort -nr | head -1)
    fi
    disksize=$(util_getNearestPower2 $disksize)
    if [ "$disksize" -lt "999" ]; then
        disksize="${disksize} GB" 
    else
        disksize="$(echo "$disksize/1000" | bc)TB"
    fi

    hwspec="$hwspec, ${numdisks} x ${disksize} $disktype"

    ## Memory
    local memory=
    local memorystr=$(echo "$sysinfo" | grep Memory | grep -v Info | cut -d':' -f2)
    local memcnt=$(echo "$memorystr" | wc -l)
    if [ -n "$memorystr" ]; then 
        [ "$memcnt" -ne "$numnodes" ] && log_warn "No memory listed for few nodes"
        memory=$(echo "$memorystr" | awk '{print $1}' | uniq)
        local gb=$(echo "$memorystr" | awk '{print $2}' | uniq | sort -nr | head -1)
        if [ "$(echo $memory | wc -w)" -gt "1" ]; then
            log_warn "Memory isn't same all node nodes. Not a homogeneous cluster"
            memory=$(echo "$memory" | sort -nr | head -1)
        fi
        memory=$(util_getNearestPower2 $memory)
        memory="${memory} ${gb}"
    else
        log_error "No memory listed on any nodes"
        memory=0
    fi

    hwspec="$hwspec, $memory RAM"

    ## Network
    local nw=
    local nwstr=$(echo "$sysinfo" | grep -A2 "Network Info" | grep -v Disk | grep NIC | sort -k2)
    if [ -n "$nwstr" ]; then
        local niccnt=$(echo "$nwstr" | wc -l)
        local nicpernode=$(echo "$niccnt/$numnodes" | bc)
        [ "$(( $niccnt % $numnodes ))" -ne "0" ] && log_warn "# of NICs do not match. Not a homogeneous cluster" && nicpernode=0
        local mtus=$(echo "$nwstr" | awk '{print $4}' | tr -d ',' | uniq)
        if [ "$(echo $mtus | wc -w)" -gt "1" ]; then
            log_warn "MTUs on the NIC(s) are not same"
            mtus=$(echo "$mtus" | sort -nr | head -1)
        fi
        local nwsp=$(echo "$nwstr" | awk '{print $8}' | tr -d ',' | uniq)
        if [ "$(echo $nwsp | wc -w)" -gt "1" ]; then
            log_warn "NIC(s) are of different speeds"
            nwsp=$(echo "$nwsp" | sort -nr | head -1)
        fi
        nw="${nicpernode} x ${nwsp}"
        [ "$mtus" -gt "1500" ] && nw="$nw (mtu : $mtus/jumbo frames)" || nw="$nw (mtu : $mtus)"
    fi
    
    hwspec="$hwspec, $nw"

    ## OS
    local os=
    local osstr=$(echo "$sysinfo" | grep -A2 "Machine Info" | grep OS | cut -d ':' -f2 | sed 's/^ //g')
    local oscnt=$(echo "$osstr" | wc -l)
    if [ -n "$osstr" ]; then 
        [ "$oscnt" -ne "$numnodes" ] && log_warn "No OS listed for few nodes"
        os=$(echo "$osstr" | awk '{print $1}' | uniq)
        local ver=$(echo "$osstr" | awk '{print $2}' | uniq | sort -nr | head -1)
        if [ "$(echo $os | wc -w)" -gt "1" ]; then
            log_warn "OS isn't same all node nodes. Not a homogeneous cluster"
            os=$(echo "$os" | sort | head -1)
        fi
        os="${os} ${ver}"
        sysspec="$sysspec, $os"
    else
        log_warn "No OS listed on any nodes"
    fi
    
    # Build MapR Spec

    ## Build & Patch
    local maprstr=$(echo "$sysinfo" | grep -A6 "MapR Info")
    if [ -n "$maprstr" ]; then 
        local maprverstr=$(echo "$maprstr" | grep Version |  cut -d':' -f2- | sed 's/^ //g')
        local maprver=$(echo "$maprverstr" | awk '{print $1}' | uniq)
        local maprpver=$(echo "$maprverstr" | grep patch | awk '{print $2,$3}' | uniq | head -1)
        if [ "$(echo $maprver | wc -w)" -gt "1" ]; then
            log_warn "Different versions of MapR installed."
            maprver=$(echo "$maprver" | sort -nr | head -1)
        fi
        [ -n "$maprpver" ] && maprver="$maprver $maprpver"

        local nummfs=$(echo "$maprstr" | grep "# of MFS" | cut -d':' -f2 | sed 's/^ //g' | uniq )
        if [ "$(echo $nummfs | wc -w)" -gt "1" ]; then
             log_warn "Different # of MFS configured on nodes"
             nummfs=$(echo "$nummfs" | sort -nr | head -1)
        fi

        local numsps=$(echo "$maprstr" | grep "# of SPs" | awk '{print $5}' | uniq )
        if [ "$(echo $numsps | wc -w)" -gt "1" ]; then
             log_warn "Different # of SPs configured on nodes"
             numsps=$(echo "$numsps" | sort -nr | head -1)
        fi
        
        local numdn=$(echo "$maprstr" | grep "mapr-fileserver" | wc -l)
        local numcldb=$(echo "$maprstr" | grep "mapr-cldb" | wc -l)
        local numtopo=$(echo "$maprstr" | grep "Topology" | awk '{print $3}' | sort | uniq)H
        if [ "$(echo $numtopo | wc -w)" -gt "1" ]; then
            numdn=$(echo "$maprstr" | grep "Topology" | awk '{print $3}' | sort | uniq -c | sort -nr | head -1 | awk '{print $1}')
        fi
        maprspec="$numnodes nodes ($numcldb CLDB, $numdn Data), $nummfs MFS, $numsps SP, $maprver"
    fi

    ## Print specifications
    echo
    log_msghead "Cluster Specs : "
    log_msg "\t H/W   : $hwspec"
    log_msg "\t Nodes : $sysspec"
    [ -n "$maprspec" ] && log_msg "\t MapR  : $maprspec" 
}

function maprutil_applyLicense(){
    if [ -n "$GLB_SECURE_CLUSTER" ]; then
        echo 'mapr' | maprlogin password  2>/dev/null
        echo 'mapr' | sudo -su mapr maprlogin password 2>/dev/null
    fi

    wget http://stage.mapr.com/license/LatestDemoLicense-M7.txt --user=maprqa --password=maprqa -O /tmp/LatestDemoLicense-M7.txt > /dev/null 2>&1
    local buildid=$(maprutil_getBuildID)
    local i=0
    local jobs=1
    while [ "${jobs}" -ne "0" ]; do
        log_info "[$(util_getHostIP)] Waiting for CLDB to come up before applying license.... sleeping 30s"
        if [ "$jobs" -ne 0 ]; then
            local licenseExists=`/opt/mapr/bin/maprcli license list | grep M7 | wc -l`
            if [ "$licenseExists" -ne 0 ]; then
                jobs=0
            else
                sleep 30
            fi
        fi
        ### Attempt using Downloaded License
        if [ "${jobs}" -ne "0" ]; then
            jobs=`/opt/mapr/bin/maprcli license add -license /tmp/LatestDemoLicense-M7.txt -is_file true > /dev/null;echo $?`;
        fi
        let i=i+1
        if [ "$i" -gt 10 ]; then
            log_error "Failed to apply license. Node may not be configured correctly"
            exit 1
        fi
    done
}

function maprutil_mountSelfHosting(){
    local ismounted=$(mount | grep -Fw "10.10.10.20:/mapr/selfhosting/")
    [ -n "$ismounted" ] && return
    for i in $(mount | grep "/mapr/selfhosting/" | cut -d' ' -f3)
    do
        timeout 20 umount -l $i > /dev/null 2>&1
    done

    [ ! -d "/home/MAPRTECH" ] && mkdir -p /home/MAPRTECH > /dev/null 2>&1
    log_info "[$(util_getHostIP)] Mounting selfhosting on /home/MAPRTECH"
    timeout 20 mount -t nfs 10.10.10.20:/mapr/selfhosting/ /home/MAPRTECH  > /dev/null 2>&1
}

## @param optional hostip
## @param rolefile
function maprutil_restartWardenOnNode() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local node=$1
    local rolefile=$2
    local stopstart=$3

     # build full script for node
    local scriptpath="$RUNTEMPDIR/restartonnode_${node: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    if [ -n "$(maprutil_isClientNode $rolefile $node)" ]; then
        return
    fi
    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath
    
    echo "maprutil_restartWarden \"$stopstart\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"   
}

## @param stop/start/restart
function maprutil_restartWarden() {
    local stopstart=$1
    local execcmd=
    if [[ -e "/etc/systemd/system/mapr-warden.service" ]]; then
        execcmd="service mapr-warden"
    elif [[ -e "/etc/init.d/mapr-warden" ]]; then
        execcmd="/etc/init.d/mapr-warden"
    elif [[ -e "/opt/mapr/initscripts/mapr-warden" ]]; then
        log_warn "warden init scripts not configured on nodes"
        execcmd="/opt/mapr/initscripts/mapr-warden"
    else
        log_warn "No mapr-warden on node"
        return
    fi
        #statements
    if [[ "$stopstart" = "stop" ]]; then
        execcmd=$execcmd" stop"
    elif [[ "$stopstart" = "start" ]]; then
        execcmd=$execcmd" start"
    else
        execcmd=$execcmd" restart"
    fi

    bash -c "$execcmd"
}

## @param optional hostip
## @param rolefile
function maprutil_restartZKOnNode() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return
    fi
    local rolefile=$2
    local stopstart=$3
    if [ -n "$(maprutil_isClientNode $rolefile $1)" ]; then
        return
    fi
    if [ -z "$stopstart" ]; then
        ssh_executeCommandasRoot "$1" "service mapr-zookeeper restart" &
    elif [[ "$stopstart" = "stop" ]]; then
        ssh_executeCommandasRoot "$1" "service mapr-zookeeper stop" &
    elif [[ "$stopstart" = "start" ]]; then
        ssh_executeCommandasRoot "$1" "service mapr-zookeeper start" &
    fi
    maprutil_addToPIDList "$!" 
}

function maprutil_removemMapRPackages(){
   
    util_removeBinaries "mapr-"
}

# @param PID 
function maprutil_addToPIDList(){
    if [ -z "$1" ]; then
        return
    fi
    [ -z "$GLB_BG_PIDS" ] && GLB_BG_PIDS=()
    GLB_BG_PIDS+=($1)
}

function maprutil_wait(){
    #log_info "Waiting for background processes to complete [${GLB_BG_PIDS[*]}]"
    for((i=0;i<${#GLB_BG_PIDS[@]};i++)); do
        local pid=${GLB_BG_PIDS[i]}
        wait $pid
        local errcode=$?
        #if [ "$errcode" -eq "0" ]; then
        #    log_info "$pid completed successfully"
        #else 
        if [ "$errcode" -ne "0" ]; then
            log_warn "Child process [$pid] exited with errorcode : $errcode"
            [ -z "$GLB_EXIT_ERRCODE" ] && GLB_EXIT_ERRCODE=$errcode
        fi
    done
    GLB_BG_PIDS=()
}

# @param timestamp
function maprutil_zipDirectory(){
    local timestamp=$1
    local tmpdir="/tmp/maprlogs/$(hostname -f)/"
    local logdir="/opt/mapr/logs"
    local buildid=$(cat /opt/mapr/MapRBuildVersion)
    local tarfile="maprlogs_$(hostname -f)_$buildid_$timestamp.tar.bz2"

    mkdir -p $tmpdir > /dev/null 2>&1
    
    cd $tmpdir && tar -cjf $tarfile -C $logdir . > /dev/null 2>&1
    # Copy configurations files 
    maprutil_copyConfsToDir "$tmpdir"
}

function maprutil_copyConfsToDir(){
    if [ -z "$1" ]; then
        return
    fi
    local todir="$1/conf"
    mkdir -p $todir > /dev/null 2>&1

    [ -e "/opt/mapr/conf" ] && cp -r /opt/mapr/conf $todir/mapr-conf/ > /dev/null 2>&1
    for i in $(ls -d /opt/mapr/hadoop/hadoop-*/)
    do
        i=${i%?};
        local hv=$(echo "$i" | rev | cut -d '/' -f1 | rev)
        [ -e "$i/conf" ] && cp -r $i/conf $todir/$hv-conf/ > /dev/null 2>&1
        [ -e "$i/etc/hadoop" ] && cp -r $i/conf $todir/$hv-conf/ > /dev/null 2>&1
    done

    for i in $(ls -d /opt/mapr/hbase/hbase-*/)
    do
        i=${i%?};
        local hbv=$(echo "$i" | rev | cut -d '/' -f1 | rev)
        [ -e "$i/conf" ] && cp -r $i/conf $todir/$hbv-conf/ > /dev/null 2>&1
    done
}

# @param host ip
# @param timestamp
function maprutil_zipLogsDirectoryOnNode(){
    if [ -z "$1" ]; then
        return
    fi

    local node=$1
    local timestamp=$2
    
    local scriptpath="$RUNTEMPDIR/zipdironnode_${node: -3}.sh"
    util_buildSingleScript "$lib_dir" "$scriptpath" "$node"
    local retval=$?
    if [ "$retval" -ne 0 ]; then
        return
    fi

    echo >> $scriptpath
    echo "##########  Adding execute steps below ########### " >> $scriptpath

    echo "maprutil_zipDirectory \"$timestamp\"" >> $scriptpath
   
    ssh_executeScriptasRootInBG "$node" "$scriptpath"
    maprutil_addToPIDList "$!"
}


# @param host ip
# @param local directory to copy the zip file
function maprutil_copyZippedLogsFromNode(){
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        log_warn "Incorrect or null arguments. Ignoring copy of the files"
        return
    fi

    local node=$1
    local timestamp=$2
    local copyto=$3
    mkdir -p $copyto > /dev/null 2>&1
    local host=$(ssh_executeCommandasRoot "$node" "echo \$(hostname -f)")
    local filetocopy="/tmp/maprlogs/$host/*$timestamp.tar.bz2"
    
    ssh_copyFromCommandinBG "root" "$node" "$filetocopy" "$copyto"
}

### END_OF_FUNCTIONS - DO NOT DELETE THIS LINE ###
