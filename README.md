# iperf3-imix-test

This is an attempt to test you network with "IMIX profile" using open-source software.

## Prerequisites
 - iptables need to be adjusted on both iPerf server and iPerf client
 - SSH configured to use RSA keys
 - basic understanding of bash
 - bc package must be installed on client's side

## Output sample
```
[root@centos6 ~]# ./udp-iperf.sh 192.168.136.4 2
iPerf3 will run 3 flows of IMIX traffic for the duration of 10 seconds:
 64-byte packets   (18 bytes of payload)   with configured bandwidth of 380,000 bits/s
 576-byte packets  (530 bytes of payload)  with configured bandwidth of 1,000,000 bits/s
 1350-byte packets (1304 bytes of payload) with configured bandwidth of 620,000 bits/s

iPerf3 was running for 10 seconds with bandwidth limit set to 2Mb/s.

Data                 Sent       Received       Lost        Drop     Bandwidth     Bandwidth
flow              packets        packets    packets        rate      (sender)    (receiver)
64-byte              5512           5345        167       3.00%      .370Mb/s      .359Mb/s
576-byte             2344           2344          0       0.00%     1.117Mb/s     1.117Mb/s
1350-byte             600             72        528      88.00%      .625Mb/s      .075Mb/s

Summary              8456           7761        695       8.00%     2.112Mb/s     1.551Mb/s
```

## IMIX traffic profile
IMIX stands for Internet Mix prepresenting traffic of various nature/size. I was unable to find any standards that identify the exact size of IMIX traffic pattern except a wiki page, which is not a standard ;)

It is a know fact, that the minimum Ethernet frame payload is 46 bytes and the maximum Ethernet frame payload is 1500 bytes for regular/low level hardware network. RFC879/RFC6691 declare minimum size for IPv4 datagram is 576 bytes. Than being said, IMIX traffic pattern could be represented in three values: 64 bytes, 576 bytes and 1500 bytes.

Wiki page for IMIX (https://en.wikipedia.org/wiki/Internet_Mix) and Cisco in its own testing tool (https://github.com/cisco-system-traffic-generator/trex-core/blob/master/scripts/stl/imix.py) use the following traffic distribution:

|Total Ethernet length|Number of packets in stream|Percent of packets|Percent of BW consumption|
|:-----:|:-----:|:-----:|:-----:|:-----:|
|64|7|58|19|
|594|4|33|50|
|1518|1|9|31|


If you use IPSec, then the maximum packet size sould be less then 1400. To be safe in terms of MTU, you can use the following values

|UDP payload length|Total Ethernet length|Percent of traffic consumption|
|:-----:|:-----:|:-----:|:-----:|
|18|64|19|
|530|576|50|
|1304|1350|31|

## Statistics
Many people on the Internet complained about iPerf3 statistics provided for UDP and I am one of them. It is not accurate at all, so I used iptables with user-defined chains to count the number of packet sent/received. 

## Ingress counters (server side)
The number of received packets can be tracked with following iptables configuration:
```
#user-defined chain
:IPERF_IN - [0:0]

#accept control traffic
-I INPUT -p tcp --dport 5001:5003 -j ACCEPT

#iPerf3 forwarding to IPERF_IN chain
-I INPUT -p udp --dport 5001:5003 -j IPERF_IN

#Rules for specific ports
-A IPERF_IN -p udp --dport 5001 -j ACCEPT
-A IPERF_IN -p udp --dport 5002 -j ACCEPT
-A IPERF_IN -p udp --dport 5003 -j ACCEPT
```

Statistics can be retrieved with the following command:
```
sudo iptables -L IPERF_IN -v -n -x
```

To reset the counters, use the following command:
```
sudo iptables -Z IPERF_IN
```

##Egress counters (client side)
The number of sent packets can be tracked with following iptables configuration:
```
#user-defined chain
:IPERF_OUT - [0:0]

#iPerf3 forwarding to IPERF_OUT chain
-A OUTPUT -p udp --dport 5000:5003 -j IPERF_OUT

#Rules for specific ports
-A IPERF_OUT -p udp --dport 5001 -j ACCEPT
-A IPERF_OUT -p udp --dport 5002 -j ACCEPT
-A IPERF_OUT -p udp --dport 5003 -j ACCEPT
```

Sumilar commands to show and resetting counters:
```
sudo iptables -L IPERF_OUT -v -n -x
```

```
sudo iptables -Z IPERF_OUT
```

## IPERF ON THE SERVER SIDE
iPerf3 could be run on the server side in daemon mode with following arguments utilizing different CPU cores:
```
iperf3 -p 5001 -s -D -A 0
iperf3 -p 5002 -s -D -A 2
iperf3 -p 5003 -s -D -A 4
```
If you do not have that many cores, then avoid -A option


## IPERF ON THE CLIENT SIDE
Script uses RSA key to send remote commands to the server (clear iptables counters), so RSA key and username are needed. You can specify these in lines 4 and 5 of the script.

If your CPU has less than 4 cores, then remove affinity parameter (-A) and its argument in lines:
 - 95, 96, 97
 - 99, 100, 101

That is all. Once it is done, you can run the script.

## Logfile
Logs are written in files with prefix of "iperf_*".