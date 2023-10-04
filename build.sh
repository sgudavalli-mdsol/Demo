#!/bin/bash

source tools/medistrano/ecs-all-func.sh

BUILD_TYPE=''

skip_docker_image_build()
{
  echo -e "\nA docker image for $GITREF ($GITSHA)\nis verified built already"
  BUILD_IMAGE=$(jq -r ".builds[] | select (.build_id==\"$ECS_PROC_ID\") | .name" $ECS_BUILD_IMAGES | head -n1)
}

build_docker_image_build()
{
   echo -e "\n----------------------------------------------------------------------------------------------"
   echo -e "Build a docker image against '$GITREF ($GITSHA)'"
   echo -e "----------------------------------------------------------------------------------------------\n"

   check_api_returned_http_code build_docker_image
   ECS_WORK_TYPE=build
   ECS_API_ENDPOINT=builds
   ecs_work_status_check

   BUILD_IMAGE=""
   while [ "$BUILD_IMAGE" = ""  ]
   do
     sleep $CHECK_INTERVAL
     check_api_returned_http_code lst_docker_builds
     BUILD_IMAGE=$(jq -r ".builds[] | select (.build_id==\"$ECS_PROC_ID\") | .name" $ECS_BUILD_IMAGES)
   done
}

build_chk_and_proc()
{
   if [ -n "$ECS_PROC_ID" ]; then
      skip_docker_image_build
   else
      build_docker_image_build
   fi
}
echo -e "##\n## Docker image build output\n##\n" > $ECS_CONF
echo -e "export CODE_REPO=$CODE_REPO" >> $ECS_CONF
echo -e "export GITREF=$GITREF" >> $ECS_CONF
echo -e "export GITSHA=$GITSHA" >> $ECS_CONF

check_api_returned_http_code lst_docker_builds

if echo $AAF_BUILD_REQ | grep -i "yes" > /dev/null 2>&1; then
   echo -e "\nAAF_BUILD_REQ=$AAF_BUILD_REQ"
   [ -n "$GITTAG" ] && GITREF=$GITTAG
   build_docker_image_build
elif [ -n "$GITTAG" ]; then
   GITREF=$GITTAG
   ECS_PROC_ID=$(jq -r ".builds[] | select (.git_ref==\"$GITREF\" and
                                            .git_sha==\"$GITSHA\") | .build_id" $ECS_BUILD_IMAGES | head -n1)
   build_chk_and_proc
else
   # if $GITREF = $GITSHA, then it means $GITREF is not a release tag. Otherwise, yes.
   if [ "$GITREF" = "$GITSHA" ]; then
      ECS_PROC_ID=$(jq -r ".builds[] | select (.git_sha==\"$GITSHA\") | .build_id" $ECS_BUILD_IMAGES | head -n1)
      build_chk_and_proc
   else
      ECS_PROC_ID=$(jq -r ".builds[] | select (.git_ref==\"$GITREF\" and
                                               .git_sha==\"$GITSHA\") | .build_id" $ECS_BUILD_IMAGES | head -n1)
      build_chk_and_proc
   fi
fi

if [ ! "$ECS_PROC_ID" ]; then
   echo -e "\nError: BUILD_ID has no value\n"
   exit 1
fi
echo -e "export BUILD_ID=$ECS_PROC_ID" >> $ECS_CONF
echo -e "export BUILD_IMAGE=$BUILD_IMAGE" >> $ECS_CONF

id_trigger_user
show_app_ecs_conf