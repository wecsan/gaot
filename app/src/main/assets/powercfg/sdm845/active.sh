#!/system/bin/sh

action=$1

init () {
  local dir=$(cd $(dirname $0); pwd)
  if [[ -f "$dir/powercfg-base.sh" ]]; then
    sh "$dir/powercfg-base.sh"
  elif [[ -f '/data/powercfg-base.sh' ]]; then
    sh /data/powercfg-base.sh
  fi
}
if [[ "$action" = "init" ]]; then
  init
  exit 0
fi

stop perfd

echo 1 > /sys/devices/system/cpu/cpu0/online
echo 1 > /sys/devices/system/cpu/cpu1/online
echo 1 > /sys/devices/system/cpu/cpu2/online
echo 1 > /sys/devices/system/cpu/cpu3/online
echo 1 > /sys/devices/system/cpu/cpu4/online
echo 1 > /sys/devices/system/cpu/cpu5/online
echo 1 > /sys/devices/system/cpu/cpu6/online
echo 1 > /sys/devices/system/cpu/cpu7/online

echo 0 > /sys/module/msm_thermal/core_control/enabled
echo 0 > /sys/module/msm_thermal/vdd_restriction/enabled
echo N > /sys/module/msm_thermal/parameters/enabled

governor0=`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`
governor4=`cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor`

if [ ! "$governor0" = "schedutil" ]; then
  echo 'schedutil' > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
fi
if [ ! "$governor4" = "schedutil" ]; then
  echo 'schedutil' > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
fi

# /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
# 300000 403200 480000 576000 652800 748800 825600 902400 979200 1056000 1132800 1228800 1324800 1420800 1516800 1612800 1689600 1766400

# /sys/devices/system/cpu/cpu4/cpufreq/scaling_available_frequencies
# 825600 902400 979200 1056000 1209600 1286400 1363200 1459200 1536000 1612800 1689600 1766400 1843200 1920000 1996800 2092800 2169600 2246400 2323200 2400000 2476800 2553600 2649600

governor_performance () {
  local dir=/sys/class/devfreq
  for file in `ls $dir`; do
    if [ -f $dir/$file/available_frequencies ]; then
      max_freq=$(awk -F ' ' '{print $NF}' $dir/$file/available_frequencies)
      if [[ "$max_freq" != "" ]]; then
        echo $file '->' $max_freq
        echo $max_freq > $dir/$file/max_freq
        echo $max_freq > $dir/$file/min_freq
      fi
    fi
  done
}

governor_restore () {
  local dir=/sys/class/devfreq
  for file in `ls $dir`; do
    if [ -f $dir/$file/available_frequencies ]; then
      min_freq=$(awk '{print $1}' $dir/$file/available_frequencies)
      if [[ "$min_freq" != "" ]]; then
        echo $file '->' $min_freq
        echo $min_freq > $dir/$file/min_freq
      fi
    fi
  done
}

if [[ "$action" == "fast" ]]; then
  governor_performance
else
  governor_restore
fi

function set_value()
{
    value=$1
    path=$2
    if [[ -f $path ]]; then
        current_value="$(cat $path)"
        if [[ ! "$current_value" = "$value" ]]; then
            chmod 0664 "$path"
            echo "$value" > "$path"
        fi;
    fi;
}

# GPU频率表
gpu_freqs=`cat /sys/class/kgsl/kgsl-3d0/devfreq/available_frequencies`
# GPU最大频率
gpu_max_freq='710000000'
# GPU最小频率
gpu_min_freq='100000000'
# GPU最小 power level
gpu_min_pl=6
# GPU最大 power level
gpu_max_pl=0
# GPU默认 power level
gpu_default_pl=`cat /sys/class/kgsl/kgsl-3d0/default_pwrlevel`
# GPU型号
gpu_model=`cat /sys/class/kgsl/kgsl-3d0/gpu_model`
# GPU调度器
gpu_governor=`cat /sys/class/kgsl/kgsl-3d0/devfreq/governor`

# MaxFrequency、MinFrequency
for freq in $gpu_freqs; do
    if [[ $freq -gt $gpu_max_freq ]]; then
        gpu_max_freq=$freq
    fi;
    if [[ $freq -lt $gpu_min_freq ]]; then
        gpu_min_freq=$freq
    fi;
done

# Power Levels
if [[ -f /sys/class/kgsl/kgsl-3d0/num_pwrlevels ]];then
    gpu_min_pl=`cat /sys/class/kgsl/kgsl-3d0/num_pwrlevels`
    gpu_min_pl=`expr $gpu_min_pl - 1`
fi;
if [[ "$gpu_min_pl" -lt 0 ]];then
    gpu_min_pl=0
fi;

if [ ! "$gpu_governor" = "msm-adreno-tz" ]; then
  echo 'msm-adreno-tz' > /sys/class/kgsl/kgsl-3d0/devfreq/governor
fi

echo $gpu_max_freq > /sys/class/kgsl/kgsl-3d0/devfreq/max_freq
echo $gpu_min_freq > /sys/class/kgsl/kgsl-3d0/devfreq/min_freq
echo $gpu_min_pl > /sys/class/kgsl/kgsl-3d0/min_pwrlevel
echo $gpu_max_pl > /sys/class/kgsl/kgsl-3d0/max_pwrlevel

function set_input_boost_freq() {
  local c0="$1"
  local c1="$2"
  local ms="$3"
  echo "0:$c0 1:$c0 2:$c0 3:$c0 4:$c1 5:$c1 6:$c1 7:$c1" > /sys/module/cpu_boost/parameters/input_boost_freq
  echo $ms > /sys/module/cpu_boost/parameters/input_boost_ms
}

function set_cpu_freq()
{
  echo $1 $2 $3 $4
  echo "0:$2 1:$2 2:$2 3:$2 4:$4 5:$4 6:$4 7:$4" > /sys/module/msm_performance/parameters/cpu_max_freq
  echo $1 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
  echo $2 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
  echo $3 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq
  echo $4 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq
}

function schedutil_cfg()
{
  set_value $2 /sys/devices/system/cpu/cpu$1/cpufreq/schedutil/down_rate_limit_us
  set_value $3 /sys/devices/system/cpu/cpu$1/cpufreq/schedutil/up_rate_limit_us
  set_value $4 /sys/devices/system/cpu/cpu$1/cpufreq/schedutil/iowait_boost_enable
}

if [ "$action" = "powersave" ]; then
  set_cpu_freq 5000 1516800 5000 1612800
  set_input_boost_freq 0 0 0

  echo 518400 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_freq
  echo 652800 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/hispeed_freq

  echo $gpu_min_pl > /sys/class/kgsl/kgsl-3d0/default_pwrlevel
  echo 0 > /proc/sys/kernel/sched_boost

elif [ "$action" = "balance" ]; then
  set_cpu_freq 5000 1766400 5000 1996800
  set_input_boost_freq 1228800 0 40

  echo 960000 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_freq
  echo 1056000 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/hispeed_freq

  echo $gpu_min_pl > /sys/class/kgsl/kgsl-3d0/default_pwrlevel
  echo 0 > /proc/sys/kernel/sched_boost

elif [ "$action" = "performance" ]; then
  set_cpu_freq 5000 1766400 5000 2649600
  set_input_boost_freq 1689600 1459200 80

  echo 1478400 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_freq
  echo 1267200 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/hispeed_freq

  echo `expr $gpu_min_pl - 1` > /sys/class/kgsl/kgsl-3d0/default_pwrlevel
  echo 0 > /proc/sys/kernel/sched_boost

elif [ "$action" = "fast" ]; then
  set_cpu_freq 5000 2500000 1267200 3500000
  set_input_boost_freq 1689600 1804800 80

  echo 1036800 > /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_freq
  echo 1420800 > /sys/devices/system/cpu/cpu4/cpufreq/schedutil/hispeed_freq

  echo `expr $gpu_min_pl - 2` > /sys/class/kgsl/kgsl-3d0/default_pwrlevel
  echo 1 > /proc/sys/kernel/sched_boost
fi
