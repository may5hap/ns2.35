# Experiments with on-off sources that transmit data for a certain
# "on" time and then are silent for a certain "off" time. The on and
# off times come from exponential distributions at specifiable rates.
# During the "on" period, the data isn't sent at a constant bit rate
# as in the existing exponential on-off traffic model in
# tools/expoo.cc but is instead sent according to the underlying
# transport (agent) protocol, such as TCP.  The "off" period is the
# same as in that traffic model.

#!/bin/sh
# the next line finds ns \
nshome=`dirname $0`; [ ! -x $nshome/ns ] && [ -x ../../../ns ] && nshome=../../..
# the next line starts ns \
export nshome; exec $nshome/ns "$0" "$@"

if [info exists env(nshome)] {
	set nshome $env(nshome)
} elseif [file executable ../../../ns] {
	set nshome ../../..
} elseif {[file executable ./ns] || [file executable ./ns.exe]} {
	set nshome "[pwd]"
} else {
	puts "$argv0 cannot find ns directory"
	exit 1
}
set env(PATH) "$nshome/bin:$env(PATH)"

source sender-app.tcl
source logging-app2.tcl
source stats.tcl

set conffile [lindex $argv 0]
#set conffile remyconf/vz4gdown.tcl
#set conffile remyconf/equisource.tcl

proc Usage {} {
    global opt argv0
    puts "Usage: $argv0 \[-simtime seconds\] \[-seed value\] \[-nsrc numSources\]"
    puts "\t\[-tr tracefile\]"
    puts "\t\[-bw $opt(bneck)] \[-delay $opt(delay)\]"
    exit 1
}

proc Getopt {} {
    global opt argc argv
#    if {$argc == 0} Usage
    for {set i 1} {$i < $argc} {incr i} {
        set key [lindex $argv $i]
        if ![string match {-*} $key] continue
        set key [string range $key 1 end]
        set val [lindex $argv [incr i]]
        set opt($key) $val
        if [string match {-[A-z]*} $val] {
            incr i -1
            continue
        }
    }
}

#
# Create a simple dumbbell topology.
#
proc create-dumbbell-topology {bneckbw delay} {
    global ns opt s gw d accessrate accessdelay nshome
    for {set i 0} {$i < $opt(nsrc)} {incr i} {
#        $ns duplex-link $s($i) $gw 10Mb 1ms DropTail
#        $ns duplex-link $gw $d $bneckbw $delay DropTail
        $ns duplex-link $s($i) $gw $accessrate($i) $accessdelay($i) $opt(gw)
        $ns queue-limit $s($i) $gw $opt(maxq)
        $ns queue-limit $gw $s($i) $opt(maxq)
        if { $opt(gw) == "XCP" } {
            # not clear why the XCP code doesn't do this automatically
            set lnk [$ns link $s($i) $gw]
            set q [$lnk queue]
            $q set-link-capacity [ [$lnk set link_] set bandwidth_ ]
            set rlnk [$ns link $gw $s($i)]
            set rq [$rlnk queue]
            $rq set-link-capacity [ [$rlnk set link_] set bandwidth_ ]
        }
    }
    if { $opt(link) == "trace" } {
        $ns simplex-link $d $gw [ bw_parse $bneckbw ] $delay $opt(gw)
#        [ [ $ns link $d $gw ] link ] trace-file "$nshome/link/tracedata/uplink-verizon4g.pps"
        source $nshome/link/trace.tcl
        $ns simplex-link $gw $d [ bw_parse $bneckbw ] $delay $opt(gw)
        [ [ $ns link $gw $d ] link ] trace-file $opt(linktrace)
    } else {
        $ns duplex-link $gw $d $bneckbw $delay $opt(gw)
    }
    $ns queue-limit $gw $d $opt(maxq)
    $ns queue-limit $d $gw $opt(maxq)    
    if { $opt(gw) == "XCP" } {
        # not clear why the XCP code doesn't do this automatically
        set lnk [$ns link $gw $d]
        set q [$lnk queue]
        $q set-link-capacity [ [$lnk set link_] set bandwidth_ ]
        set rlnk [$ns link $d $gw]
        set rq [$rlnk queue]
        $rq set-link-capacity [ [$rlnk set link_] set bandwidth_ ]
    }
}

proc create-sources-sinks {} {
    global ns opt s d src recvapp tp protocols protosinks f

    set numsrc $opt(nsrc)
    if { [string range $opt(tcp) 0 9] == "TCP/Linux/"} {
        set linuxcc [ string range $opt(tcp) 10 [string length $opt(tcp)] ]
        set opt(tcp) "TCP/Linux"
    }

    if { $opt(tcp) == "DCTCP" } {
        Agent/TCP set dctcp_ true
        Agent/TCP set ecn_ 1
        Agent/TCP set old_ecn_ 1
        Agent/TCP set packetSize_ $opt(pktsize)
        Agent/TCP/FullTcp set segsize_ $opt(pktsize)
        Agent/TCP set window_ 1256
        Agent/TCP set slow_start_restart_ false
        Agent/TCP set tcpTick_ 0.01
        Agent/TCP set minrto_ 0.2 ; # minRTO = 200ms
        Agent/TCP set windowOption_ 0
        Queue/RED set bytes_ false
        Queue/RED set queue_in_bytes_ true
        Queue/RED set mean_pktsize_ $opt(pktsize)
        Queue/RED set setbit_ true
        Queue/RED set gentle_ false
        Queue/RED set q_weight_ 1.0
        Queue/RED set mark_p_ 1.0
        Queue/RED set thresh_ 65
        Queue/RED set maxthresh_ 65
        DelayLink set avoidReordering_ true
        set opt(tcp) "TCP/Newreno"
    }

    for {set i 0} {$i < $numsrc} {incr i} {

        if { $opt(cycle_protocols) == true } {
            set opt(tcp) [lindex $protocols [expr $i % $opt(nsrc)]]
            set opt(sink) [lindex $protosinks [expr $i % $opt(nsrc)]]
            if { [string range $opt(tcp) 0 9] == "TCP/Linux/"} {
                set linuxcc [ string range $opt(tcp) 10 [string length $opt(tcp)] ]
                set opt(tcp) "TCP/Linux"
            }

            if { $opt(tcp) == "DCTCP" } {
                Agent/TCP set dctcp_ true
                Agent/TCP set ecn_ 1
                Agent/TCP set old_ecn_ 1
                Agent/TCP set packetSize_ $opt(pktsize)
                Agent/TCP/FullTcp set segsize_ $opt(pktsize)
                Agent/TCP set window_ 1256
                Agent/TCP set slow_start_restart_ false
                Agent/TCP set tcpTick_ 0.01
                Agent/TCP set minrto_ 0.2 ; # minRTO = 200ms
                Agent/TCP set windowOption_ 0
                Queue/RED set bytes_ false
                Queue/RED set queue_in_bytes_ true
                Queue/RED set mean_pktsize_ $opt(pktsize)
                Queue/RED set setbit_ true
                Queue/RED set gentle_ false
                Queue/RED set q_weight_ 1.0
                Queue/RED set mark_p_ 1.0
                Queue/RED set thresh_ 65
                Queue/RED set maxthresh_ 65
                DelayLink set avoidReordering_ true
                set opt(tcp) "TCP/Newreno"
            }
        }
        set tp($i) [$ns create-connection-list $opt(tcp) $s($i) $opt(sink) $d $i]
        set tcpsrc [lindex $tp($i) 0]
        set tcpsink [lindex $tp($i) 1]
        if { [info exists linuxcc] } { 
            $ns at 0.0 "$tcpsrc select_ca $linuxcc"
            $ns at 0.0 "$tcpsrc set_ca_default_param linux debug_level 2"
        }

        if { [string first "Rational" $opt(tcp)] != -1 } {
            if { $opt(tracewhisk) == "all" || $opt(tracewhisk) == $i } {
                $tcpsrc set tracewhisk_ 1
                puts "tracing ON for connection $i: $opt(tracewhisk)"
            } else {
                $tcpsrc set tracewhisk_ 0
                puts "tracing OFF for connection $i: $opt(tracewhisk)"
            }
        }
        $tcpsrc set window_ $opt(rcvwin)
        $tcpsrc set packetSize_ $opt(pktsize)
        
        if { [info exists opt(tr)] } {
            $tcpsrc trace cwnd_
            $tcpsrc trace rtt_
            $tcpsrc trace maxseq_
            $tcpsrc trace ack_
            if { $opt(tcp) == "TCP/Rational" } {
                $tcpsrc trace _intersend_time
            }
            $tcpsrc attach $f
        }

        set src($i) [ $tcpsrc attach-app $opt(app) ]
        puts "Setting ID $i $tcpsrc"
        $src($i) setid $i $tcpsrc
        set recvapp($i) [new LoggingApp $i]
        $recvapp($i) attach-agent $tcpsink
        $ns at 0.0 "$recvapp($i) start"
    }
}

proc showstats {final} {
    global ns opt stats

    for {set i 0} {$i < $opt(nsrc)} {incr i} {
        set res [$stats($i) results]
        set totalbytes [lindex $res 0]
        set totaltime [lindex $res 1]
        set totalrtt [lindex $res 2]
        set nsamples [lindex $res 3]
        set nconns [lindex $res 4]

        if { $totaltime > 0.0 && $nsamples > 0} {
            set throughput [expr 8.0 * $totalbytes / $totaltime]
            set avgrtt [expr 1000*$totalrtt/$nsamples]
            if { $avgrtt > 0.0 } {
                set utility [expr log($throughput) - [expr $opt(alpha)*log($avgrtt)]]
            } else {
                set utility [expr log($throughput)
            }
            if { $final == True } {
                puts [ format "FINAL %d %d %.3f %.1f %.2f %.2f %d" $i $totalbytes [expr $throughput/1000000.0] $avgrtt [expr 100.0*$totaltime/$opt(simtime)] $utility $nconns ]
            } else {
                puts [ format "----- %d %d %.3f %.1f %.2f %.2f %d" $i $totalbytes [expr $throughput/1000000.0] $avgrtt [expr 100.0*$totaltime/$opt(simtime)] $utility $nconns]
            }
        }
    }   
}


# proc showstats {final} {
#     global ns opt stats

#     for {set i 0} {$i < $opt(nsrc)} {incr i} {
#         set res [$stats($i) results]
#         set totalbytes [lindex $res 0]
#         set totaltime [lindex $res 1]
#         set totalrtt [lindex $res 2]
#         set nsamples [lindex $res 3]
#         set nconns [lindex $res 4]

#         if { $nsamples > 0 } {
#             set avgrtt [expr 1000*$totalrtt/$nsamples]
#         } else {
#             set avgrtt 0.0
#         }
#         if { $totaltime > 0.0} {
#             set throughput [expr 8.0 * $totalbytes / $totaltime]
#             set utility [expr log($throughput) - [expr $opt(alpha)*log($avgrtt)]]
#             if { $final == True } {
#                 puts [ format "FINAL %d %d %.3f %.1f %.4f %.2f %d" $i $totalbytes [expr $throughput/1000000.0] $avgrtt [expr 100.0*$totaltime/$opt(simtime)] $utility $nconns ]
#             } else {
#                 puts [ format "----- %d %d %.3f %.1f %.4f %.2f %d" $i $totalbytes [expr $throughput/1000000.0] $avgrtt [expr 100.0*$totaltime/$opt(simtime)] $utility $nconns]
#             }
#         }
#     }
# }

proc finish {} {
    global ns opt stats src recvapp
    global f
    for {set i 0} {$i < $opt(nsrc)} {incr i} {
        set sapp $src($i)
        $sapp dumpstats
        [$sapp set stats_] showstats
    }

    if { [info exists f] } {
        $ns flush-trace
        close $f           
    }                                                                                                       
    exit 0
}

## MAIN ##

source $conffile
puts "Reading params from $conffile"

Getopt

set_access_params $opt(nsrc)

if { $opt(gw) == "XCP" } {
    remove-all-packet-headers       ; # removes all except common
    add-packet-header Flags IP TCP XCP ; # hdrs reqd for validation
}
    
if { $opt(seed) >= 0 } {
    ns-random $opt(seed)
}

set ns [new Simulator]

Queue set limit_ $opt(maxq)
#RandomVariable/Pareto set shape_ 0.5

if { [info exists opt(tr)] } {
    # if we don't set up tracing early, trace output isn't created!!
    set f [open $opt(tr).tr w]
    $ns trace-all $f
}

set flowfile flowcdf-allman-icsi.tcl

# create sources, destinations, gateways
for {set i 0} {$i < $opt(nsrc)} {incr i} {
    set s($i) [$ns node]
}
set d [$ns node];               # destination for all the TCPs
set gw [$ns node];              # bottleneck router

if { $opt(ontype) == "flowcdf" } {
    source $flowfile
}
create-dumbbell-topology $opt(bneck) $opt(delay)
create-sources-sinks


if { $opt(cycle_protocols) == true } {
    for {set i 0} {$i < $opt(nsrc)} {incr i} {
        puts "$i: [lindex $protocols $i]"
    }
} else {
    if { [info exists linuxcc] } {
        puts "Results for $opt(tcp)/$linuxcc $opt(gw) $opt(sink) over $opt(simtime) seconds:"
    } else {
        puts "Results for $opt(tcp) $opt(gw) $opt(sink) over $opt(simtime) seconds:"
    }
}

#puts "     SrcID Bytes Mbits/s AvgRTT On% Utility NumConns"

$ns at $opt(simtime) "finish"

$ns run

