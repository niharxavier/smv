#!/bin/bash
CURRENT_DIR=`pwd`
SCRIPTDIR=`dirname "$(readlink -f "$0")"`
cd $SCRIPTDIR/../../..
FIREMODELS_ROOT=`pwd`
cd $CURRENT_DIR

NOBOUNDS=


#---------------------------------------------
#                   Usge
#---------------------------------------------

function Usage {
  scriptname=`basename $0`
  echo "Usage: $scriptname [options] casename"
  echo ""
  echo "This script generates an mp4 animation of an FDS case by running multiple copies of smokeview"
  echo "where each copy produces images which are then combined to form the animation"
  echo ""
  echo "-B      - don't compute bounds at smokeview startup"
  echo "-c file - config file"
  echo "-e path - full path of smokeview executable."
  echo "     [default: $SMOKEVIEW]"
  echo "-h - show this message"
  echo "-i - use installed smokeview"
  echo "-O - only output frame from the last smokeview instance (debug option)"
  echo "-v - show but do not run the  script generated by this script"
  exit
}

#---------------------------------------------
#                   is_smokeview_installed
#---------------------------------------------

is_smokeview_installed()
{
  out=/tmp/program.out.$$
  smokeview -v >& $out
  notfound=`cat $out | tail -1 | grep "not found" | wc -l`
  rm $out
  if [ "$notfound" == "1" ] ; then
    echo "***error: smokeview is not installed.  Add it to your PATH or"
    echo "          build the smv repo version of smokeview and use it"
    return 1
  fi
  return 0
}

#---------------------------------------------
#                   OUTPUT_VIEWPOINTS
#---------------------------------------------

OUTPUT_VIEWPOINTS ()
{
  cat $viewpointmenu | awk -F"," '{ print $1" ",$2}'
}

#---------------------------------------------
#                   CHECK_WRITE
#---------------------------------------------

CHECK_WRITE ()
{
  DIR=$1
  if [ ! -e $DIR ]; then
    mkdir $DIR
    if [ ! -e $DIR ]; then
      echo "***error: the directory $DIR could not be created"
      return 1
    fi
  fi
  touch $DIR/.test
  if [ ! -e $DIR/.test ]; then
    echo "***error: the directdory $DIR cannot be written too"
    return 1
  fi
  rm $DIR/.test
}


#---------------------------------------------
#                   OUTPUT_SLICES
#---------------------------------------------

OUTPUT_SLICES ()
{
  cat $slicefilemenu | awk -F"," '{ print $1" ",$2," ",$3," ",$4}'
}

#---------------------------------------------
#                   wait_cases_end
#---------------------------------------------

wait_cases_end()
{
  while [[ `qstat -a | awk '{print $2 $4 $10}' | grep $(whoami) | grep ${JOBPREFIX} | grep -v 'C$'` != '' ]]; do
     JOBS_REMAINING=`qstat -a | awk '{print $2 $4 $10}' | grep $(whoami) | grep ${JOBPREFIX} | grep -v 'C$' | wc -l`
     echo "Waiting for ${JOBS_REMAINING} cases to complete."
     sleep 1
  done
}

#---------------------------------------------
#                   restore_user_state
#---------------------------------------------

restore_user_state()
{
  USERCONFIG=$1
  if [ -e $USERCONFIG ]; then
    source $USERCONFIG
    if [ "$USER_NPROCS" != "" ]; then
      NPROCS=$USER_NPROCS
    fi
    if [ "$USER_QUEUE" != "" ]; then
      QUEUE=$USER_QUEUE
    fi
    if [ "$USER_RENDERDIR" != "" ]; then
      RENDERDIR=$USER_RENDERDIR
    fi
    if [ "$USER_MOVIEDIR" != "" ]; then
      MOVIEDIR=$USER_MOVIEDIR
    fi
    if [ "$USER_EMAIL" != "" ]; then
      EMAIL=$USER_EMAIL
    fi
    if [ "$USER_SHARE" != "" ]; then
      SHARE=$USER_SHARE
    fi
  fi
}
#---------------------------------------------
#                   restore_state
#---------------------------------------------

restore_state()
{
  if [ -e $GLOBALCONFIG ]; then
    source $GLOBALCONFIG
    NPROCS=${SLICE2MP4_NPROCS}
    QUEUE=${SLICE2MP4_QUEUE}
    RENDERDIR=${SLICE2MP4_RENDERDIR}
    MOVIEDIR=${SLICE2MP4_MOVIEDIR}
    EMAIL=${SLICE2MP4_EMAIL}
    SHARE=${SLICE2MP4_SHARE}
    MODE360=${SLICE2MP4_MODE360}
    if [ "${SLICE2MP4_WEBHOST}" != "" ]; then
      SMV_WEBHOST=${SLICE2MP4_WEBHOST}
    fi
  fi
  LOCALCONFIG=$CONFIGDIR/slice2mp4_${input}
  if [ -e $LOCALCONFIG ]; then
    source $LOCALCONFIG
    viewpoint=$SLICE2MP4_VIEWPOINT
    viewpointd=$SLICE2MP4_VIEWPOINTD
    COLORBAR=${SLICE2MP4_COLORBAR}
    if [ "$COLORBAR" == "" ]; then
      COLORBAR="0"
    fi
    TIMEBAR=${SLICE2MP4_TIMEBAR}
    if [ "$TIMEBAR" == "" ]; then
      TIMEBAR="0"
    fi

#*** don't show colorbar or timebar in 360 mode
    if [ "$MODE360" == "1" ]; then
      COLORBAR="0"
      TIMEBAR="0"
    else
      MODE360="0"
    fi
    FONTSIZE=${SLICE2MP4_FONTSIZE}
    if [ "$FONTSIZE" == "" ]; then
      FONTSIZE="0"
    fi
  fi
}

#---------------------------------------------
#                   save_state
#---------------------------------------------

save_state()
{
  echo "#/bin/bash"                             >  $GLOBALCONFIG
  echo "export SLICE2MP4_NPROCS=$NPROCS"        >> $GLOBALCONFIG
  echo "export SLICE2MP4_QUEUE=$QUEUE"          >> $GLOBALCONFIG
  echo "export SLICE2MP4_RENDERDIR=$RENDERDIR"  >> $GLOBALCONFIG
  echo "export SLICE2MP4_MOVIEDIR=$MOVIEDIR"    >> $GLOBALCONFIG
  echo "export SLICE2MP4_EMAIL=$EMAIL"          >> $GLOBALCONFIG
  echo "export SLICE2MP4_SHARE=$SHARE"          >> $GLOBALCONFIG
  echo "export SLICE2MP4_MODE360=$MODE360"      >> $GLOBALCONFIG
  if [ "$SMV_WEBHOST" == "" ]; then
    echo "export SLICE2MP4_WEBHOST=none"        >> $GLOBALCONFIG
  else
    echo "export SLICE2MP4_WEBHOST=$SMV_WEBHOST" >> $GLOBALCONFIG
  fi
  
  LOCALCONFIG=$CONFIGDIR/slice2mp4_${input}
  echo "#/bin/bash"                                   >  $LOCALCONFIG
  echo "export SLICE2MP4_VIEWPOINT=\"$viewpoint\""    >> $LOCALCONFIG
  echo "export SLICE2MP4_VIEWPOINTD=\"$viewpointd\""  >> $LOCALCONFIG
  echo "export SLICE2MP4_COLORBAR=$COLORBAR"          >> $LOCALCONFIG
  echo "export SLICE2MP4_FONTSIZE=$FONTSIZE"          >> $LOCALCONFIG
  echo "export SLICE2MP4_TIMEBAR=$TIMEBAR"            >> $LOCALCONFIG
}

#---------------------------------------------
#                  writeini
#---------------------------------------------

writeini ()
{
cat << EOF > $smv_inifilename
SHOWFRAMELABEL
 0
EOF
if [ "$valmin" != "" ]; then
cat << EOF >> $smv_inifilename
V2_SLICE
 0 $valmin 0 $valmax $slice_quantity_short

EOF
fi
cat << EOF >> $smv_inifilename
SHOWCOLORBARS 
  $COLORBAR
SHOWTIMEBAR
  $TIMEBAR
SHOWTIMELABEL
  $TIMEBAR
FONTSIZE
  $FONTSIZE
EOF
if [ "$MODE360" == "1" ]; then
cat << EOF >> $smv_inifilename
RENDERFILETYPE
 0 1 4
EOF
fi
}

#---------------------------------------------
#                  generate_images
#---------------------------------------------

select_options ()
{
while true; do
echo ""
slice_quantity=`trim "$slice_quantity"`
slice_dir=`trim "$slice_dir"`
slice_pos=`trim "$slice_pos"`
echo "          slice: $slice_quantity/$slice_dir=$slice_pos "
if [ "$have_bounds" == "1" ]; then
  echo "       min, max: $valmin $slice_quantity_unit, $valmax $slice_quantity_unit"
else
  echo "         bounds: default"
fi
if [ "$COLORBAR" == "1" ]; then
  echo "      color bar: show"
else
  echo "      color bar: hide"
fi
if [ "$TIMEBAR" == "1" ]; then
  echo "       time bar: show"
else
  echo "       time bar: hide"
fi
if [ "$FONTSIZE" == "0" ]; then
  echo "      font size: small"
else
  echo "      font size: large"
fi
if [ "$viewpointd" != "" ]; then
  echo "      viewpoint: $viewpointd"
else
  echo "      viewpoint: $viewpoint"
fi
if [ "$MODE360" == "0" ]; then
  echo "     movie mode: rectangular"
else
  echo "     movie mode: 360"
fi
echo ""
echo "        PNG dir: $RENDERDIR"
echo "        mp4 dir: $MOVIEDIR"
echo "            url: $SMV_WEBHOST"
#if [ "$SHARE" == "" ]; then
#  echo "      processes: $NPROCS, node sharing off"
#else
#  echo "      processes: $NPROCS, node sharing on"
#fi
echo "      processes: $NPROCS"
echo "          queue: $QUEUE"
echo "          email: $EMAIL"
echo ""
echo "s - select slice"
echo "b - set bounds"
if [ "$COLORBAR" == "0" ]; then
  echo "C - show color bar"
else
  echo "C - hide color bar"
fi
if [ "$TIMEBAR" == "0" ]; then
  echo "T - show time bar"
else
  echo "T - hide time bar"
fi
  echo "F - toggle font size"
  echo "3 - toggle 360 mode"
  echo "v - set viewpoint"

  echo ""
  echo "r - set PNG dir "
  echo "a - set mp4 dir"
  echo "u - set web url"
  if [ "$SMV_WEBHOST_default" != "" ]; then
    echo "U - use default url ($SMV_WEBHOST_default)"
  fi
  echo "m - set email address"
  echo ""
  echo "p - set number of processes"
#  echo "S - toggle node sharing"
  echo "q - set queue"
  echo ""
  echo "w - save settings"
  echo "1 - create MP4 animation"
  echo "2 - create MP4 animation then exit"
  echo "x - exit"
  read -p "option: " ans
  if [ "$ans" == "a" ]; then
    read -p "   enter animation directory: " MOVIEDIR
    CHECK_WRITE $MOVIEDIR
    continue
  fi
  if [ "$ans" == "u" ]; then
    read -p "   enter web url:" SMV_WEBHOST
    continue
  fi
  if [ "$SMV_WEBHOST_default" != "" ]; then
    if [ "$ans" == "U" ]; then
      SMV_WEBHOST=$SMV_WEBHOST_default 
      continue
    fi
  fi
  if [ "$ans" == "b" ]; then
    read -p "   set $slice_quantity_short min: " valmin
    read -p "   set $slice_quantity_short max: " valmax
    have_bounds=1
    writeini
    continue;
  fi
  if [ "$ans" == "3" ]; then
    if [ "$MODE360" == "0" ]; then
      MODE360="1"
      COLORBAR_SAVE=$COLORBAR
      TIMEBAR_SAVE=$TIMEBAR

#*** don't show colorbar or timebar in 360 mode

      COLORBAR="0"
      TIMEBAR="0"
    else
      MODE360="0"
      if [ "$COLORBAR_SAVE" != "" ]; then
        COLORBAR=$COLORBAR_SAVE
      fi
      if [ "$TIMEBAR_SAVE" != "" ]; then
        TIMEBAR=$TIMEBAR_SAVE
      fi
    fi
    writeini
    continue
  fi
  if [ "$ans" == "C" ]; then
    if [ "$COLORBAR" == "0" ]; then
      if [ "$MODE360" == "0" ]; then
        COLORBAR="1"
      else
        echo "***warning: color bar not shown in 360 movie mode"
      fi
    else
      COLORBAR="0"
    fi
    writeini
    continue
  fi
  if [ "$ans" == "F" ]; then
    if [ "$FONTSIZE" == "0" ]; then
      FONTSIZE="1"
    else
      FONTSIZE="0"
    fi
    writeini
    continue
  fi
  if [ "$ans" == "T" ]; then
    if [ "$TIMEBAR" == "0" ]; then
      if [ "$MODE360" == "0" ]; then
        TIMEBAR="1"
      else
        echo "***warning: time bar not shown in 360 movie mode"
      fi
    else
      TIMEBAR="0"
    fi
    writeini
    continue
  fi
  if [ "$ans" == "r" ]; then
    read -p "   enter image frame directory: " RENDERDIR
    CHECK_WRITE $RENDERDIR
    continue
  fi
  if [ "$ans" == "s" ]; then
    select_slicefile
    continue
  fi
  if [ "$ans" == "S" ]; then
    if [ "$SHARE" == "" ]; then
      SHARE="-T"
    else
      SHARE=""
    fi
    continue
  fi
  if [ "$ans" == "m" ]; then
    read -p "   enter email address: " EMAIL
    continue
  fi
  if [ "$ans" == "p" ]; then
    read -p "   enter number of processes: " NPROCS
    continue
  fi
  if [ "$ans" == "q" ]; then
    read -p "   enter queue: " QUEUE
    continue
  fi
  if [ "$ans" == "v" ]; then
    select_viewpoint
    continue
  fi
  if [ "$ans" == "x" ]; then
    save_state
    exit
  fi
  if [ "$ans" == "w" ]; then
    save_state
  fi
  if [[ "$ans" == "1" ]] ||  [[ "$ans" == "2" ]]; then
    writeini
    GENERATE_SCRIPTS $slice_index
    make_movie
    if [ "$ans" == "2" ]; then
      save_state
      exit
    fi
  fi
done
}

#---------------------------------------------
#                   select_viewpoint
#---------------------------------------------

select_viewpoint ()
{
while true; do
  OUTPUT_VIEWPOINTS
  read -p "Select viewpoint: " ans
  if [ "$ans" == "d" ]; then
    viewpoint=
    return 0
  fi
  if [ "$ans" == "x" ]; then
    viewpoint=
    viewpointd="XMIN"
    return 0
  fi
  if [ "$ans" == "X" ]; then
    viewpoint=
    viewpointd="XMAX"
    return 0
  fi
  if [ "$ans" == "y" ]; then
    viewpoint=
    viewpointd="YMIN"
    return 0
  fi
  if [ "$ans" == "Y" ]; then
    viewpoint=
    viewpointd="YMAX"
    return 0
  fi
  if [ "$ans" == "z" ]; then
    viewpoint=
    viewpointd="ZMIN"
    return 0
  fi
  if [ "$ans" == "Z" ]; then
    viewpoint=
    viewpointd="ZMAX"
    return 0
  fi
  re='^[0-9]+$'
  if ! [[ $ans =~ $re ]]; then
    echo "***error: $ans is an invalid selection"
    continue
  fi
  if [[ $ans -ge 1 ]] && [[ $ans -le $nviewpoints ]]; then
    viewpoint_index=$ans
    viewpoint=`cat $viewpointmenu | awk -v ind="$viewpoint_index" -F"," '{ if($1 == ind){print $2} }'`
    viewpointd=
    return 0
  else
    echo index $ans out of bounds
  fi
done
}

#---------------------------------------------
#                   select_slicefile
#---------------------------------------------

select_slicefile ()
{
have_bounds=
while true; do
  OUTPUT_SLICES
  re='^[0-9]+$'
  read -p "Select slice file: " ans
  if ! [[ $ans =~ $re ]]; then
    echo "***error: $ans is an invalid selection"
    continue
  fi
  if [[ "$ans" -ge 1 ]] && [[ "$ans" -le "$nslices" ]]; then
    slice_index=$ans
    img_basename=${input}_slice_${slice_index}
    smv_scriptname=$SMVSCRIPTDIR${img_basename}.ssf
    img_scriptname=$SMVSCRIPTDIR${img_basename}.sh
    smv_inifilename=$SMVSCRIPTDIR${img_basename}.ini

    slice_quantity=`cat $slicefilemenu | awk -v ind="$slice_index" -F"," '{ if($1 == ind){print $2} }'`
    slice_quantity=`trim "$slice_quantity"`

    slice_quantity_short=`grep -A 4 SLCF $smvfile | grep "$slice_quantity" -A 1 | head -2 | tail -1`
    slice_quantity_short=`trim "$slice_quantity_short"`

    slice_quantity_unit=`grep -A 4 SLCF $smvfile | grep "$slice_quantity" -A 2 | tail -1`
    slice_quantity_unit=`trim "$slice_quantity_unit"`

    slice_dir=`cat $slicefilemenu | awk -v ind="$slice_index" -F"," '{ if($1 == ind){print $3} }'`
    slice_pos=`cat $slicefilemenu | awk -v ind="$slice_index" -F"," '{ if($1 == ind){print $4} }'`
    slice_dir=$(echo $slice_dir | tr -d ' ')
    slice_pos=$(echo $slice_pos | tr -d ' ')
    if [ "$slice_dir" == "1" ]; then
      slice_dir="X"
    fi
    if [ "$slice_dir" == "2" ]; then
      slice_dir="Y"
    fi
    if [ "$slice_dir" == "3" ]; then
      slice_dir="Z"
    fi
    return 0
  else
    echo index $ans out of bounds
  fi
done
}

#---------------------------------------------
#                   trim
#---------------------------------------------

trim()
{
  local var="$*"
# remove leading whitespace characters
  var="${var#"${var%%[![:space:]]*}"}"
# remove trailing whitespace characters
  var="${var%"${var##*[![:space:]]}"}"   
  printf '%s' "$var"
}

#---------------------------------------------
#                   make_movie
#---------------------------------------------

make_movie() {

  if [ "$v_opt" != "" ]; then
    echo ""
    echo "image generatingscript: $img_scriptnme"
    cat $img_scriptname
    return
  fi

# render images

  bash $img_scriptname
  start_time="$(date -u +%s.%N)"
  wait_cases_end
  end_time="$(date -u +%s.%N)"
  render_time="$(bc <<<"$end_time-$start_time")"
  nimages=`ls -l $RENDERDIR/${img_basename}*.png | wc -l`
  echo ""
  echo "images generated: $nimages"
  last=`ls -l $RENDERDIR/${img_basename}*.png | tail -1 | awk '{print $9}'`
  echo "      last image: $last"
  echo ""

# make movie

  start_time="$(date -u +%s.%N)"
  nerrs=`grep Error ${input}_f*_s$NPROCS.err | wc -l`
  if [ "$nerrs" != "0" ]; then 
    grep Error ${input}_f*_s$NPROCS.err | tail
  else
    animation_file=$MOVIEDIR/${img_basename}.mp4
    echo Creating $animation_file
    $MAKEMOVIE -i $RENDERDIR -o $MOVIEDIR $img_basename $img_basename >& /dev/null
    if [ "$EMAIL" != "" ]; then
      if [ -e $animation_file ]; then
        if [[ "$SMV_WEBHOST" != "" ]] && [[ "$SMV_WEBHOST" != "none" ]]; then
          echo "URL: $SMV_WEBHOST/${img_basename}.mp4 sent to $EMAIL"
          echo "$SMV_WEBHOST/${img_basename}.mp4" | mail -s "$slice_quantity slice generated" $EMAIL
        else
          echo "$animation_file slice generated"
          echo "" | mail -s "$slice_quantity slice generated" $EMAIL
        fi
      fi
    fi
  fi
  end_time="$(date -u +%s.%N)"
  movie_time="$(bc <<<"$end_time-$start_time")"
  echo ""
  echo render time=$render_time
  echo mp4 time=$movie_time
}

#---------------------------------------------
#                   GENERATE_SCRIPT
#---------------------------------------------

GENERATE_SCRIPTS ()
{
  ind=$1
  cat << EOF > ${smv_scriptname}
RENDERDIR
  $RENDERDIR
UNLOADALL
LOADINIFILE
 $smv_inifilename
EOF
if [ "$viewpointd" != "" ]; then
  cat << EOF >> ${smv_scriptname}
SETVIEWPOINT
  $viewpointd

EOF
fi
if [ "$viewpoint" != "" ]; then
  cat << EOF >> ${smv_scriptname}
SETVIEWPOINT
  $viewpoint
EOF
fi
  cat << EOF >> ${smv_scriptname}
LOADSLICERENDER
EOF
  slice_quantity=`cat $slicefilemenu | awk -v ind="$ind" -F"," '{ if($1 == ind){print $2} }'`
  cat $slicefilemenu | awk -v ind="$ind" -F"," '{ if($1 == ind){print $2"\n" $3 $4} }' >> $smv_scriptname
  cat << EOF >> $smv_scriptname
  $img_basename 
  0 1
EOF
  echo ""

# turn off node sharing for now
SHARE=
  cat << EOF > $img_scriptname
#!/bin/bash
NPROCS=$NPROCS
QUEUE=$QUEUE
SMOKEVIEW="$SMOKEVIEW"
NOBOUNDS="$NOBOUNDS"
SMOKEVIEWBINDIR="$SMOKEVIEWBINDIR"
QSMV="${FIREMODELS_ROOT}/smv/Utilities/Scripts/qsmv.sh $SHARE $O_opt $v_opt"
\$QSMV -j $JOBPREFIX -P \$NPROCS -q \$QUEUE -e \$SMOKEVIEW \$NOBOUNDS -b \$SMOKEVIEWBINDIR -c $smv_scriptname $input
EOF
chmod +x $img_scriptname
}

#----------------------- beginning of script --------------------------------------

#*** initialize variables

NARGS=$#
if [ "$NARGS" == "0" ]; then
  Usage
  exit
fi  

RENDERDIR=.
MOVIEDIR=/var/www/html/`whoami`
if [ ! -e $MOVIEDIR ]; then
  MOVIEDIR=.
fi
NPROCS=20
QUEUE=batch4
MODE360=0
slice_index=
HELP_ALL=
JOBPREFIX=SV_
GENERATE_IMAGES=
MAKE_MOVIE=
COLORBAR="0"
TIMEBAR="0"
FONTSIZE="1"

CONFIGDIR=$HOME/.smokeview
if [ ! -e $CONFIGDIR ]; then
  mkdir $CONFIGDIR
fi
GLOBALCONFIG=$CONFIGDIR/slice2mp4_global

SMVSCRIPTDIR=
touch test.$$ >& /dev/null
if [ -e test.$$ ]; then
  rm test.$$
else
  SMVSCRIPTDIR=${CONFIGDIR}/
fi


# define repo variables

CURDIR=`pwd`
SCRIPTDIR=`dirname "$0"`
cd $SCRIPTDIR/../../..
ROOTDIR=`pwd`
SMVREPO=$ROOTDIR/smv
BOTREPO=$ROOTDIR/bot
cd $CURDIR
SMOKEVIEWBINDIR=$BOTREPO/Bundlebot/smv/for_bundle
SMOKEVIEW=$SMVREPO/Build/smokeview/intel_linux_64/smokeview_linux_64
if [ ! -e $SMOKEVIEW ]; then
  SMOKEVIEW=$SMVREPO/Build/smokeview/intel_linux_64/smokeview_linux_test_64
fi
QSMV=$SMVREPO/Utilities/Scripts/qsmv.sh
MAKEMOVIE=$SMVREPO/Utilities/Scripts/make_movie.sh
EMAIL=
SHARE=
v_opt=
O_opt=
USER_CONFIG=
SMV_WEBHOST_default=
if [ "$SMV_WEBHOST" != "" ]; then
  SMV_WEBHOST_default=$SMV_WEBHOST
fi

#---------------------------------------------
#                  parse command line options 
#---------------------------------------------

while getopts 'Bc:e:hiOv' OPTION
do
case $OPTION  in
  B)
   NOBOUNDS="-B"
   ;;
  c)
   USER_CONFIG="$OPTARG"
   ;;
  e)
   SMOKEVIEW="$OPTARG"
   ;;
  h)
   Usage
   exit
   ;;
  i)
   is_smokeview_installed || exit 1
   SMOKEVIEW=`which smokeview`
   ;;
  O)
   O_opt="-O"
   ;;
  v)
   v_opt="-v"
   ;;
esac
done
shift $(($OPTIND-1))

if [ ! -e $SMOKEVIEW ]; then
  echo "***error: smokeview not found at $SMOKEVIEW"
  exit 1
fi

input=$1
restore_state
if [ "$USER_CONFIG" != "" ]; then
  restore_user_state $USER_CONFIG
fi

smvfile=$1.smv
slicefilemenu=$CONFIGDIR/$1.slcf

if [ ! -e $smvfile ]; then
  echo "***error: $smvfile does not exist"
  exit
fi

$SMOKEVIEW -info $input >& /dev/null

# get viewpoint menu (optional)

nviewpoints=0
viewpointmenu=$CONFIGDIR/$1.viewpoints
if [ -e $viewpointmenu ]; then
  nviewpoints=`cat $viewpointmenu | wc -l`
  (( nviewpoints -= 3 ))
else
  echo "index   viewpoint"  > $viewpointmenu
  echo "d   delete"        >> $viewpointmenu
fi
echo "    x   XMIN"    >> $viewpointmenu
echo "    X   XMAX"    >> $viewpointmenu
echo "    y   YMIN"    >> $viewpointmenu
echo "    Y   YMAX"    >> $viewpointmenu
echo "    z   ZMIN"    >> $viewpointmenu
echo "    Z   ZMAX"    >> $viewpointmenu


# get slice file menu (required)

if [ ! -e $slicefilemenu ]; then
  echo "*** error: $slicefilemenu does not exist"
  exit
fi

nslices=`cat $slicefilemenu | wc -l`
(( nslices -= 2 ))
if [ $nslices  -eq 0 ]; then
  echo "*** error:  No slice files were found in $smvfile"
  exit
fi

select_slicefile
writeini

select_options

save_state


