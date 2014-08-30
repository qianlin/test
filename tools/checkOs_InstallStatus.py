#!/usr/bin/python

## ################################################################################
## the package and lib that must install:
##
## OpenIPMI
##  yum install OpenIPMI-python
##
## Pexpect:Version 3.3 or higher
##  caution: a lower version will cause some error like "timeout nonblocking() in read" when you log to a host by ssh
##      wget https://pypi.python.org/packages/source/p/pexpect/pexpect-3.3.tar.gz
##      tar xvf pexpect-3.3.tar.gz
##      cd pexpect-3.3
##      python setup install
##
##        
## Be aware:
##    2014-08-24 : using multiprocessing.dummy to archieve multi-thread instead of multi-processing with multiprocessing
##         in multi-process, the function pssh will cause error like "local variable 's' referenced before assignment"
##      
## ################################################################################

import os
import sys
import pexpect
import pxssh
from multiprocessing.dummy import Pool
import subprocess
import OpenIPMI
import time
def pssh((hostname,username,password,cli)):
    print 'host:%s,cli:%s' % (hostname,cli)
    output=''
    try:
        s = pxssh.pxssh()
        s.login(hostname,username,password)
        s.sendline(cli)
        s.expect(pexpect.EOF, timeout=None)
        output=s.before
        print output
    except Exception,e:
        print '\nException Occur in ssh to host %s ,Error is:\n %s' % (hostname, str(e))
    finally:
	s.close()
    return [hostname,output]

def pxe((hostname,commandList)):
    print "pxe %s" % hostname
    result = 0
    for command in commandList :
        print 'pxe command:%s' % command
        res=subprocess.call(command.split(" "))

        if res == 1:
            result = 1
            print 'pxe error in host %s' % hostname
            break

    return [hostname, result]

def rebootAndInstall(hosts,timeinterval=15):
    """
    a function to reboot the hosts ,using single-thread.
    """
     # TimeInterval=15
    RebootHostInPerInterval=1
    
    with open('restartError.log','w') as file:
        file.truncate()

    while True:
        for i in range(1,RebootHostInPerInterval+1) :
            if hosts :
                commandList = []
                commandList.append("ipmitool -l lanplus -H %s -U admin -P admin chassis bootdev pxe" % (hosts[0]))
                commandList.append("ipmitool -I lanplus -H %s -U admin -P admin power reset" % (hosts[0]))
                result = pxe((hosts[0],commandList))
                 
                if result[1] == 1:
                    with open('restartError.log','a') as file:
                        file.write(result[0]+'\n')
                 
                #print 'host :%s ,restart state: %s' % (result[0],result[1])
                del hosts[0]

        if hosts:
            time.sleep(timeinterval)
        else:
            break


def checkOsIsFresh(hosts,username,password,timeinterval=86400,multiProcessCount = 10):
    """
    a function to check the hosts' os are new install one,using the multi-thread.
    the default timeinterval that judge the fresh os is default as 1 day.
    return :
        [errorList,oldOsHost]
    """
    
    oldOsHost = []
    errorList = []
    cli = "stat /lost+found/ | grep Modify | awk -F ' ' {'print $2,$3,$4'};"
    cli += "exit $?" ## auto logout
    pool = Pool(processes=multiProcessCount)
    res=pool.map_async(pssh,((host,username,password,cli) for host in hosts))
    result=res.get()

#    import time 
    import datetime
    import string
    for output in result:
        if output[1] and output[1] != '' :
            timeArr=output[1].split('\n')[1].split(' ')
            realTimeStruct = time.strptime(timeArr[0]+' '+timeArr[1].split('.')[0],'%Y-%m-%d %H:%M:%S')
            realTime = datetime.datetime(*realTimeStruct[:6])
            osInstallTime_UTC = None
            utcDelta=string.atoi(timeArr[2][1:])
            if '+' in timeArr[2]:
                osInstallTime_UTC = realTime + datetime.timedelta(hours=-1*(utcDelta/100))
            elif '-' in timeArr[2]:
                osInstallTime_UTC = realTime + datetime.timedelta(hours=1*(utcDelta/100))
            
            hostOsTimeList.append((output[0],osInstallTime_UTC))
        else:
            errorList.append(output[0])
            print 'Host %s connection failed' % output[0]

    curTime = datetime.datetime.utcnow()
    print 'current Utc Time :%s' % curTime

	
    for host in hostOsTimeList :
        # print (curTime - host[1]).seconds
        if  (curTime - host[1]).seconds > NewOSFilterInterval :
            print 'host %s \'OS is not a fresh one' % host[0]
            oldOsHost.append(host[0])
    if oldOsHost :
        print 'These Hosts\' Os are not reinstall: \n'
        print oldOsHost
    pool.close()
    pool.join()
    return [errorList,oldOsHost]



if __name__ == '__main__':
    
    hostList = []
    errorList = []
    hostOsTimeList = []
	
    net='10.1.0.'
    pxenet='10.0.0.'
	
    username='root'
    password='root'
	
    #unit:second, be sure that the time in your host and server are normal.be regardless of time zone,the code will auto hanlde the timezone issue.
    NewOSFilterInterval = 60 * 60 ## 
	
    for i in range(100,105+1):
        hostList.append(net+str(i))
    for i in range(129,144+1):
        hostList.append(net+str(i))

    result=checkOsIsFresh(hostList,username,password,NewOSFilterInterval)

    print 'error'
    print result[0]
    print 'old'
    print result[1] 
    # add host to the `reboot` list to reboot them ,in a single-thread function with a resonable time interval which you need to set according. 
    # the time interval avoid a shot to the power provider when lots of compute hosts need to restart.
    waitRebootHost = result[1] #oldOsHost # errorList
    reboot =[]
    for host in waitRebootHost:
        reboot.append(pxenet+host[7:])

    rebootAndInstall(reboot)
