#!/bin/bash
#
#
#
# IMPORTANT NOTE: THIS SCRIPT IS TO BE REPLACED BY THE MORE PORTABLE
#                 check_system_crontabs.sh.
#                 It is only kept here until we are confident the non-bash
#                 version is stable.
#
#
#
# check_system_crontabs.bash
#
# Script to check and see if any system (f)crontabs have changed, and if so 
# build a fcrontab file from /etc/crontab, /etc/fcrontab and files from
# /etc/cron.d/ and notify fcron about the change.
#
# WARNING : - if you run this script, your system fcrontab will be overridden
#             by the content of /etc/crontab, /etc/fcrontab, /etc/cron.d :
#             save the content of your system fcrontab first if necessary.
#
#           - you should not have the same lines in /etc/crontab
#             and /etc/fcrontab, in which case the jobs would get run twice.
#             (/etc/crontab may for example be used for Vixie-cron compatible
#              lines, and /etc/fcrontab for the other ones)
#
#           - you must understand that the contents of all the mentionned
#             files will go to a single file : the system fcrontab.
#             This means that you should pay attention to the global option
#             settings and environment variable assignments, which may
#             affect the other files too while you thought it wouldn't.
#             
# This script was originally created for a Debian server. A number of
# Debian packages like to drop files in /etc/cron.d/ and it would be nice
# to have something automatically create a system fcrontab file and notify
# fcron when those files change, so the system administrator doesn't have
# to try and keep up with it all manually.
#
# It is planned that such feature is integreated directly in fcron
# in the future (in a cleaner and more efficient way). Until then,
# this script should be useful.
#
# I recommend running this script using dnotify or a similar program
# (dnotify wait for a change in a file or a directory, and run a command
# when it happens), with a something like that:
# dnotify -b -p 1 -q 0 -MCDR /etc /etc/cron.d -e /usr/local/sbin/check_system_crontabs
# in your boot scripts.
#
# Because we don't want the system fcrontab to be generated every few seconds
# if the sys admin is working in /etc/ (the script has probably been called
# by dnotify because of a change in /etc, but it may be a file not related
# to fcron), the script will by default sleep so as to avoid being run too
# often. The default sleep time is 30 seconds, and can be adjusted by changing
# DEFAULT_SLEEP_TIME_BEFORE_REBUILD below, or by passing -s X, where X is
# the number of seconds to sleep.  X can be 0.
#
# If you can't use dnotify, you should run this script from the system fcrontab
# with a line like this:
#
# @ 1 /usr/local/sbin/check_system_crontabs -s 0
#
# To force an immediate rebuild at the commandline try:
#   check_system_crontabs -f -i
#
# For more help on command-line options:
#   check_system_crontabs -h
#
# Changelog
# =========
# Date        Author             Description
# ----        ------             -----------
# 2004/11/12  maasj@dm.org       Original version
# 2005/02/24  Thibault Godouet   Modified to be used with dnotify 
#                                + bug fixes and enhancement.
# 2005/04/27  Daniel Himler      Security enhancements and cleanups.
# 2005/09/14  Damon Harper       Command lines options, cleanups.
#

##############################
# DEFAULT CONFIGURATION

DEFAULT_SLEEP_TIME_BEFORE_REBUILD=30
DEFAULT_CROND_DIR=/etc/cron.d
DEFAULT_CRONTAB_FILE=/etc/crontab
DEFAULT_FCRONTAB_FILE=/etc/fcrontab

FCRONTAB_PROG=/usr/bin/fcrontab
FCRONTABS_DIR=/var/spool/fcron

# END OF DEFAULT CONFIGURATION
##############################

FCRONTAB_FILE_TMP=

cleanup() {
  # remove temporary file (if any)
  [ -e "$FCRONTAB_FILE_TMP" ] && rm -f $FCRONTAB_FILE_TMP
}
trap "eval cleanup" INT TERM HUP

if [ -x "`type -p mktemp`" ]; then
	FCRONTAB_FILE_TMP=`mktemp /tmp/fcrontab.XXXXXX`
else
	FCRONTAB_FILE_TMP=/tmp/fcrontab.$$
fi

info() {
  [ -n "$VERBOSE" ] && echo "$@" >&2
}

die() {
  echo check_system_crontabs: "$@" >&2
  echo Try check_system_crontabs -h for help. >&2
  exit 1
}

usage() {
  cat <<_EOF_ >&2
Description: Rebuild the systab file from various system crontabs.
Usage: check_system_crontabs [options]
  OPTIONS:
    -v          Verbose; tell what is happening.
    -f          Force rebuild, even if no changes are found.
    -s SECONDS  Sleep for SECONDS before rebuilding.
                Default: $DEFAULT_SLEEP_TIME_BEFORE_REBUILD seconds.
    -i          Interactive use with no delay; same as -s 0.
    -p PATHNAME Full path to or filename of the fcrontab binary; use this
                only if it cannot be found automatically.
    -F FILE     System fcrontab file (default $DEFAULT_FCRONTAB_FILE).
    -C FILE     System crontab file (default $DEFAULT_CRONTAB_FILE).
    -D DIR      System crontab directory (default $DEFAULT_CROND_DIR).
    -h          This help text.
_EOF_
  exit
}

SLEEP_TIME_BEFORE_REBUILD="$DEFAULT_SLEEP_TIME_BEFORE_REBUILD"
CROND_DIR="$DEFAULT_CROND_DIR"
CRONTAB_FILE="$DEFAULT_CRONTAB_FILE"
FCRONTAB_FILE="$DEFAULT_FCRONTAB_FILE"
FCRONTAB_PROG=
VERBOSE=
FORCE=

# read command line arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
  -v)
    VERBOSE=true
    ;;
  -f)
    FORCE=true
    ;;
  -s)
    SLEEP_TIME_BEFORE_REBUILD="$2"
    shift
    ;;
  -i)
    SLEEP_TIME_BEFORE_REBUILD=0
    ;;
  -p)
    FCRONTAB_PROG="$2"
    shift
    ;;
  -F)
    FCRONTAB_FILE="$2"
    shift
    ;;
  -C)
    CRONTAB_FILE="$2"
    shift
    ;;
  -D)
    CROND_DIR="$2"
    shift
    ;;
  -h)
    usage
    ;;
  *)
    die "Invalid option: $1!"
    ;;
  esac
  shift
done

# find fcrontab executable path
if [ -n "$FCRONTAB_PROG" ]; then
  [ -d "$FCRONTAB_PROG" ] && FCRONTAB_PROG="$FCRONTAB_PROG/fcrontab"
  [ ! -x "$FCRONTAB_PROG" ] && die "Invalid fcrontab executable or path specified with -p!"
else
  if [ -x "`type -p fcrontab`" ]; then
    FCRONTAB_PROG="`type -p fcrontab`"
  elif [ -x /usr/bin/fcrontab ]; then
    FCRONTAB_PROG=/usr/bin/fcrontab
  elif [ -x /usr/local/bin/fcrontab ]; then
    FCRONTAB_PROG=/usr/local/bin/fcrontab
  else
    die "Unable to locate fcrontab binary! Specify with -p."
  fi
fi

# sanity check
if [ -z "$CROND_DIR" -o -z "$CRONTAB_FILE" -o -z "$FCRONTAB_FILE" ]; then
  die "Must specify all system crontab files."
fi

# Function to scan for valid files in $CROND_DIR
crond_files()
{
  [ ! -d $CROND_DIR ] && return
  local FILES=`echo $CROND_DIR/*`
  local FILE
  [ "$FILES" = "$CROND_DIR/*" ] && return
  for FILE in $FILES; do
    if [ ! -d $FILE -a $FILE = "${FILE%\~}" ]; then
      echo $FILE
    fi
  done
}


# Function to build up a system crontab and tell fcron it's changed
rebuild_and_notify()
{
  logger -i -p cron.notice -t "check_system_crontabs" "Rebuilding the system fcrontab..."

  # put a warning message at the top of the file
  echo -e "########################################" > $FCRONTAB_FILE_TMP
  echo -e "# WARNING!!!  DO NOT EDIT THIS FILE!!! #" >> $FCRONTAB_FILE_TMP
  echo -e "########################################" >> $FCRONTAB_FILE_TMP
  echo -e "# Do not edit this file!  It is automatically generated from" >> $FCRONTAB_FILE_TMP
  echo -e "# the $CRONTAB_FILE, the $FCRONTAB_FILE and $CROND_DIR/* files whenever one of" >> $FCRONTAB_FILE_TMP
  echo -e "# those files is changed.\n#\n\n" >> $FCRONTAB_FILE_TMP

  # include the standard system crontab file if it exists and is not a symbolic link
  if [ -f $CRONTAB_FILE -a ! -L $CRONTAB_FILE ]; then
    echo -e "\n\n########################################\n# $CRONTAB_FILE\n########################################\n" >> $FCRONTAB_FILE_TMP
    cat $CRONTAB_FILE >> $FCRONTAB_FILE_TMP
  fi

  # print a nice filename header for each file in /etc/cron.d/
  # and include its contents into the new fcron system crontab
  for i in `crond_files` ; do
    echo -e "\n\n########################################\n# $i\n########################################\n" >> $FCRONTAB_FILE_TMP
    cat $i >> $FCRONTAB_FILE_TMP
  done

  # include the system fcrontab file if it exists and is not a symbolic link
  if [ -f $FCRONTAB_FILE -a ! -L $FCRONTAB_FILE ]; then
    echo -e "\n\n########################################\n# $FCRONTAB_FILE\n########################################\n" >> $FCRONTAB_FILE_TMP
    cat $FCRONTAB_FILE >> $FCRONTAB_FILE_TMP
  fi

  # Replace "@hourly" style Vixie cron extensions which fcron doesn't parse
  sed -i -e "s/@yearly/0 0 1 1 */g" -e "s/@annually/0 0 1 1 */g" -e "s/@monthly/0 0 1 * */g" -e "s/@weekly/0 0 * * 0/g" -e "s/@daily/0 0 * * */g" -e "s/@midnight/0 0 * * */g" -e "s/@hourly/0 * * * */g" $FCRONTAB_FILE_TMP

  # notify fcron about the updated file
  $FCRONTAB_PROG $FCRONTAB_FILE_TMP -u systab
}

NEED_REBUILD=0

# by default, sleep to avoid too numerous executions of this script by dnotify.
if [ -n "$SLEEP_TIME_BEFORE_REBUILD" -a "$SLEEP_TIME_BEFORE_REBUILD" != 0 ]; then
  if ! sleep $SLEEP_TIME_BEFORE_REBUILD; then
    # sleep time was invalid or sleep interrupted by signal!
    cleanup
    exit 1
  fi
fi

# First check if we're forcing a rebuild:
if [ -n "$FORCE" ]; then

  NEED_REBUILD=1

else

  if [ -d $CROND_DIR ]; then
 
    # This test works for file creation/deletion (deletion is not detected
    # by the next test)
    if [ $CROND_DIR -nt $FCRONTABS_DIR/systab.orig ]; then

      info "Changes detected in $CROND_DIR"
      NEED_REBUILD=1

    else

      # Test each one and see if it's newer than our timestamp file
      for i in `crond_files` ; do
        if [ $i -nt $FCRONTABS_DIR/systab.orig ]; then

          info "Changes detected in $CROND_DIR"
          NEED_REBUILD=1

        fi
      done

    fi

  fi

  # Test the standard /etc/crontab file and see if it has changed
  if [ -f $CRONTAB_FILE -a $CRONTAB_FILE -nt $FCRONTABS_DIR/systab.orig ]; then

    info "Changes detected in $CRONTAB_FILE"
    NEED_REBUILD=1

  fi

  # Test the standard /etc/fcrontab file and see if it has changed
  if [ -f $FCRONTAB_FILE -a $FCRONTAB_FILE -nt $FCRONTABS_DIR/systab.orig ]; then

    info "Changes detected in $FCRONTAB_FILE"
    NEED_REBUILD=1

  fi

fi

if [ $NEED_REBUILD -eq 1 ]; then

  info "Rebuilding fcron systab."
  rebuild_and_notify

elif [ -n "$VERBOSE" ]; then

  info "Not rebuilding fcron systab; no changes found."

fi

cleanup
