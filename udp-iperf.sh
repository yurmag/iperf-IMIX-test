#!/bin/bash

# a path to the rsa key and username to access the remote server
RSA_KEY="/root/.ssh/id_rsa"
USERNAME="root"

# if the number of args is not 3
if [ $# -lt 2 ]; then
	echo "Usage: $(basename "$0") <server_ip> BANDWIDTH [TIME]"
	exit
fi

# RE is the regexp for IPv4 address
# first part is non-zero number that is less than 255 followed by dot
RE='^(([1-9])|([1-9][0-9])|1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.'
# next is any number from 0 to 255 followed by dot (two times)
RE+='((1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){2}'
# last is any number from 0 to 255 followed by dot 
RE+='(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$'

if [[ ! $1 =~ $RE ]]; then
	echo "IP address is invalid! Usage: $(basename "$0") <server_ip> BANDWIDTH [TIME]"
	exit
fi

ping -c1 -q $1 &>/dev/null
STATUS=$( echo $? )
if [[ ! $STATUS == 0 ]] ; then
	echo "Server is unchearcable!"
	exit
fi

if [ $# = 3 ]; then
	TIME=$3
else
	TIME="10"
fi

SERVER_IP=$1

# Bandwidth for traffic with is composed from:
# user specified BW(arg[2]) is interpreted as value in Megabits.
# This value must be multiplied by 1 000 000 (conversion to bits) and
# devided by 8, since BW limitation is applied per flow and iPerf is
# run with 8 flows. Effectively these two operations can be combined 
# into one multiplication by 125 000.
# Multiplication factor for each packet size is based on the amount 
# of BW is expected to be used by each traffic pattern:
#  - 64-byte the factor is 0.19 (19 percent of all traffic)
#  - 576-byte the factor is 0.5 (50 percent of all traffic)
#  - 1350-byte the factor is 0.31 (31 percent of all traffic)

# if you use multuplication factor of 0.19 for small packets,
# and calculate effective bandwidth, it will not match. 
# multiplication factor of 0.04 was found empirically. this 
# value gives the most accurate traffic pattern for small packets

BW_64=$(printf "%0.f" $( echo "$2 * 125000 * 0.04" | bc ) )
BW_576=$(printf "%0.f" $( echo "$2 * 125000 * 0.50" | bc ) )
BW_1350=$(printf "%0.f" $( echo "$2 * 125000 * 0.31" | bc ) )

# the following variables are used to indicate the expected level of
# bandwidth utilization
BW_64_REF=$(printf "%0.f" $( echo "$2 * 1000000 * 0.19" | bc ) )
BW_576_REF=$(printf "%0.f" $( echo "$2 * 1000000 * 0.50" | bc ) )
BW_1350_REF=$(printf "%0.f" $( echo "$2 * 1000000 * 0.31" | bc ) )

TIMESTAMP=$(date '+%F_%H-%M-%S')
> iperf_$TIMESTAMP.txt

# clearing iptables counters
ssh -i $RSA_KEY $USERNAME@$SERVER_IP "sudo iptables -Z IPERF_IN"
sudo iptables -Z IPERF_OUT

# printing iptables counters to the screen; they are supposed to be zeros
# echo; sudo iptables -L IPERF_OUT -v -n -x
# echo; ssh -i $RSA_KEY $USERNAME@$SERVER_IP "sudo iptables -L IPERF_IN -v -n -x"
# echo

# printing iptables counters to a temporary file; they are supposed to be zeros
> iptables.tmp
sudo iptables -L IPERF_OUT -v -n -x >> iptables.tmp
ssh -i $RSA_KEY $USERNAME@$SERVER_IP "sudo iptables -L IPERF_IN -v -n -x" >> iptables.tmp

printf "%s\n" "iPerf3 will run 3 flows of IMIX traffic for the duration of $TIME seconds:"
printf "%s %'d bits/s\n" " 64-byte packets   (18 bytes of payload)   with configured bandwidth of" $BW_64_REF 
printf "%s %'d bits/s\n" " 576-byte packets  (530 bytes of payload)  with configured bandwidth of" $BW_576_REF 
printf "%s %'d bits/s\n" " 1350-byte packets (1304 bytes of payload) with configured bandwidth of" $BW_1350_REF

printf "%s\n" "iPerf3 will run 3 flows of IMIX traffic for the duration of $TIME seconds:" >> iperf_$TIMESTAMP.txt
printf "%s %'d bits/s\n" " 64-byte packets   (18 bytes of payload)   with configured bandwidth of" $BW_64_REF  >> iperf_$TIMESTAMP.txt
printf "%s %'d bits/s\n" " 576-byte packets  (530 bytes of payload)  with configured bandwidth of" $BW_576_REF  >> iperf_$TIMESTAMP.txt
printf "%s %'d bits/s\n" " 1350-byte packets (1304 bytes of payload) with configured bandwidth of" $BW_1350_REF >> iperf_$TIMESTAMP.txt

echo "iperf3 -u -c $SERVER_IP -p 5001 -i 10 -t $TIME -l 18 -A 0 -T 64-byte_ip_payload -Z -P 8 -b $BW_64 -V &" > ./iperf_cpu0_results.tmp
echo "iperf3 -u -c $SERVER_IP -p 5002 -i 10 -t $TIME -l 530 -A 2 -T 576-byte_ip_payload -Z -P 8 -b $BW_576 -V &" > ./iperf_cpu1_results.tmp
echo "iperf3 -u -c $SERVER_IP -p 5003 -i 10 -t $TIME -l 1304 -A 4 -T 1350-byte_ip_payload -Z -P 8 -b $BW_1350 -V" > ./iperf_cpu2_results.tmp

iperf3 -u -c $SERVER_IP -p 5001 -i 10 -t $TIME -l 18 -A 0 -T 64-byte_ip_payload -Z -P 8 -b $BW_64 -V >> ./iperf_cpu0_results.tmp &
iperf3 -u -c $SERVER_IP -p 5002 -i 10 -t $TIME -l 530 -A 2 -T 576-byte_ip_payload -Z -P 8 -b $BW_576 -V >> ./iperf_cpu1_results.tmp &
iperf3 -u -c $SERVER_IP -p 5003 -i 10 -t $TIME -l 1304 -A 4 -T 1350-byte_ip_payload -Z -P 8 -b $BW_1350 -V >> ./iperf_cpu2_results.tmp

sleep 1
echo 

# appending the results of iPerf to a single file
cat iperf_cpu*.tmp >> iperf_$TIMESTAMP.txt

# printing iptables counters to the screen
# echo; sudo iptables -L IPERF_OUT -v -n -x
# echo; ssh -i $RSA_KEY $USERNAME@$SERVER_IP "sudo iptables -L IPERF_IN -v -n -x"
# echo

# printing iptables counters to separate files
sudo iptables -L IPERF_OUT -v -n -x > iptables_out.tmp
ssh -i $RSA_KEY $USERNAME@$SERVER_IP "sudo iptables -L IPERF_IN -v -n -x" > iptables_in.tmp

cat iptables.tmp >> iperf_$TIMESTAMP.txt
echo >> iperf_$TIMESTAMP.txt
cat iptables_out.tmp >> iperf_$TIMESTAMP.txt
echo >> iperf_$TIMESTAMP.txt
cat iptables_in.tmp >> iperf_$TIMESTAMP.txt
echo >> iperf_$TIMESTAMP.txt

# FLOW_64_IN/OUT represents the number of packet received/sent
FLOW_64_IN=$(cat iptables_in.tmp | grep 5001 | awk '{print $1}')
FLOW_64_OUT=$(cat iptables_out.tmp | grep 5001 | awk '{print $1}')
FLOW_576_IN=$(cat iptables_in.tmp | grep 5002 | awk '{print $1}')
FLOW_576_OUT=$(cat iptables_out.tmp | grep 5002 | awk '{print $1}')
FLOW_1350_IN=$(cat iptables_in.tmp | grep 5003 | awk '{print $1}')
FLOW_1350_OUT=$(cat iptables_out.tmp | grep 5003 | awk '{print $1}')
SUMMARY_IN=$(echo "$FLOW_64_IN + $FLOW_576_IN + $FLOW_1350_IN" | bc)
SUMMARY_OUT=$(echo "$FLOW_64_OUT + $FLOW_576_OUT + $FLOW_1350_OUT" | bc)

FLOW_64_LOST=$(echo "$FLOW_64_OUT - $FLOW_64_IN" | bc)
FLOW_576_LOST=$(echo "$FLOW_576_OUT - $FLOW_576_IN" | bc)
FLOW_1350_LOST=$(echo "$FLOW_1350_OUT - $FLOW_1350_IN" | bc)
SUMMARY_LOST=$(echo "$FLOW_64_LOST + $FLOW_576_LOST + $FLOW_1350_LOST" | bc)

FLOW_64_DROP_RATE=$(printf "%0.2f" $(echo "$FLOW_64_LOST * 100 / $FLOW_64_OUT" | bc -l) )
FLOW_576_DROP_RATE=$(printf "%0.2f" $(echo "$FLOW_576_LOST * 100 / $FLOW_576_OUT" | bc -l) )
FLOW_1350_DROP_RATE=$(printf "%0.2f" $(echo "$FLOW_1350_LOST * 100 / $FLOW_1350_OUT" | bc -l) )
SUMMARY_DROP_RATE=$(printf "%0.2f" $(echo "$SUMMARY_LOST * 100 / $SUMMARY_OUT" | bc -l) )

# Bandwidth is counted with the following formula:
#  IFG + Preamble + Ethernet + IP + UDP + payload + CRS
#  12  +    8     +    14    + 20 +  8  + payload +   4 = 66 + payload

# 64-bytes:   payload is 18, which results in 84 bytes per frame
# 576-bytes:  payload is 530, which results in 596 bytes per frame
# 1350-bytes: payload is 1304, which results in 1370 bytes per frame
# Next, bytes must be converted to megabits, which results in
# multiplication by 8 and division by 1 000 000, or multiplication by 0.000008

FLOW_64_BW_IN=$( echo "scale=3; ($FLOW_64_IN * 84 * 0.000008)/($TIME)" | bc ) 
FLOW_576_BW_IN=$( echo "scale=3; ($FLOW_576_IN * 596 * 0.000008)/($TIME)" | bc ) 
FLOW_1350_BW_IN=$( echo "scale=3; ($FLOW_1350_IN * 1304 * 0.000008)/($TIME)" | bc ) 
SUMMARY_BW_IN=$(echo "$FLOW_64_BW_IN + $FLOW_576_BW_IN + $FLOW_1350_BW_IN" | bc )

FLOW_64_BW_OUT=$( echo "scale=3; ($FLOW_64_OUT * 84 * 0.000008)/($TIME)" | bc ) 
FLOW_576_BW_OUT=$( echo "scale=3; ($FLOW_576_OUT * 596 * 0.000008)/($TIME)" | bc ) 
FLOW_1350_BW_OUT=$( echo "scale=3; ($FLOW_1350_OUT * 1304 * 0.000008)/($TIME)" | bc ) 
SUMMARY_BW_OUT=$(echo "$FLOW_64_BW_OUT + $FLOW_576_BW_OUT + $FLOW_1350_BW_OUT" | bc )

echo "iPerf3 was running for "$TIME" seconds with bandwidth limit set to "$2"Mb/s."
echo
printf "%-10s%15s%15s%11s%12s%14s%14s\n" "Data" "Sent" "Received" "Lost" "Drop" "Bandwidth" "Bandwidth"
printf "%-10s%15s%15s%11s%12s%14s%14s\n" "flow" "packets" "packets" "packets" "rate" "(sender)" "(receiver)"

printf "%-10s%15s%15s%11d%11.2f%%%10s%s%10s%s\n" "64-byte" $FLOW_64_OUT $FLOW_64_IN $FLOW_64_LOST $FLOW_64_DROP_RATE $FLOW_64_BW_OUT "Mb/s" $FLOW_64_BW_IN "Mb/s"
printf "%-10s%15s%15s%11d%11.2f%%%10s%s%10s%s\n" "576-byte" $FLOW_576_OUT $FLOW_576_IN $FLOW_576_LOST $FLOW_576_DROP_RATE $FLOW_576_BW_OUT "Mb/s" $FLOW_576_BW_IN "Mb/s"
printf "%-10s%15s%15s%11d%11.2f%%%10s%s%10s%s\n" "1350-byte" $FLOW_1350_OUT $FLOW_1350_IN $FLOW_1350_LOST $FLOW_1350_DROP_RATE $FLOW_1350_BW_OUT "Mb/s" $FLOW_1350_BW_IN "Mb/s"
echo
printf "%-10s%15s%15s%11d%11.2f%%%10s%s%10s%s\n" "Summary" $SUMMARY_OUT $SUMMARY_IN $SUMMARY_LOST $SUMMARY_DROP_RATE $SUMMARY_BW_OUT "Mb/s" $SUMMARY_BW_IN "Mb/s"

echo >> iperf_$TIMESTAMP.txt
echo "iPerf3 was running for "$TIME" seconds with bandwidth limit set to "$2"Mb/s." >> iperf_$TIMESTAMP.txt
echo >> iperf_$TIMESTAMP.txt
printf "%-10s%15s%15s%11s%12s%14s%14s\n" "Flow" "Sent" "Received" "Lost" "Drop" "Bandwidth" "Bandwidth" >> iperf_$TIMESTAMP.txt
printf "%-10s%15s%15s%11s%12s%14s%14s\n" "    " "packets" "packets" "packets" "rate" "(sender)" "(receiver)" >> iperf_$TIMESTAMP.txt
printf "%-10s%15s%15s%11d%11.2f%%%10s%s%10s%s\n" "64-byte" $FLOW_64_OUT $FLOW_64_IN $FLOW_64_LOST $FLOW_64_DROP_RATE $FLOW_64_BW_OUT "Mb/s" $FLOW_64_BW_IN "Mb/s" >> iperf_$TIMESTAMP.txt
printf "%-10s%15s%15s%11d%11.2f%%%10s%s%10s%s\n" "576-byte" $FLOW_576_OUT $FLOW_576_IN $FLOW_576_LOST $FLOW_576_DROP_RATE $FLOW_576_BW_OUT "Mb/s" $FLOW_576_BW_IN "Mb/s" >> iperf_$TIMESTAMP.txt
printf "%-10s%15s%15s%11d%11.2f%%%10s%s%10s%s\n" "1350-byte" $FLOW_1350_OUT $FLOW_1350_IN $FLOW_1350_LOST $FLOW_1350_DROP_RATE $FLOW_1350_BW_OUT "Mb/s" $FLOW_1350_BW_IN "Mb/s" >> iperf_$TIMESTAMP.txt
echo >> iperf_$TIMESTAMP.txt
printf "%-10s%15s%15s%11d%11.2f%%%10s%s%10s%s\n" "Summary" $SUMMARY_OUT $SUMMARY_IN $SUMMARY_LOST $SUMMARY_DROP_RATE $SUMMARY_BW_OUT "Mb/s" $SUMMARY_BW_IN "Mb/s" >> iperf_$TIMESTAMP.txt

rm -f *.tmp

echo
echo "iPerf3 logs are in the file: iperf_$TIMESTAMP.txt"

exit
