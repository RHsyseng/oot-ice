#!/bin/bash

set -eu


## udev rules just in case for RHEL9

exit_on_error () {
  local rc="$1"

  if [[ $rc -ne 0 ]]; then
    echo "ERROR: $rc"
    exit $rc
  fi
}

print_usage () {
cat <<- END_OF_HELP
    usage: $(basename $0) [-h] [-r] [-c] [-k] <ice_vers>

    The environment variable REGISTRY must be set.
    This is the registry that the driver container will be pushed to.

    Build the Intel out of tree ice driver for Redhat OCP
      -h: Print this help.
      -o: Use this specific OCP version.
          This option must be given if the KUBECONFIG env variable is not set
          or an OCP version other than the KUBECONFIG cluster version is desired.
      -r: Build the RT version of the OCP kernel.
          Ignored when -k is specified.
      -c: Use this custom kernel devel RPM package to build against.
          The RPM file must be in the current directory.
      -k: Version of the custom kernel given by the -c option.
          This argument must be specified if a '-c' is specified.
      -p: Apply patches found in the patches directory.
          Patches must be named nnnn-Patch-Name.patch and will be applied in the
          order of the number given in 'nnnn'

END_OF_HELP
}


build_image () {
  DTK_IMAGE=$(oc adm release info --image-for=driver-toolkit quay.io/openshift-release-dev/ocp-release:${OCP_VER}-x86_64)
  echo "Building for kernel:${KERNEL_VER} on OCP:${OCP_VER}"
  echo "DTKI for OCP:${OCP_VER} : ${DTK_IMAGE}"

  TEMP_DIR=$(basename $(mktemp -d -p .))

  wget https://github.com/intel/ethernet-linux-ice/releases/download/v${DRIVER_VER}/ice-${DRIVER_VER}.tar.gz  -O ${TEMP_DIR}/ice-${DRIVER_VER}.tar.gz
  tar xzf ${TEMP_DIR}/ice-${DRIVER_VER}.tar.gz -C ${TEMP_DIR}/
  DRIVER_SRC=${TEMP_DIR}/ice-${DRIVER_VER}
  if [[ ${APPLY_PATCHES} == "yes" ]]; then
    for f in `find $PWD/patches/${DRIVER_VER} -type f -name '*.patch'`; do echo "Applying patch $f"; patch -d ${DRIVER_SRC} -p1 < "$f"; done;
  fi

  podman build --no-cache -f Dockerfile . \
    --build-arg IMAGE=${BASE_IMAGE} \
    --build-arg BUILD_IMAGE=${DTK_IMAGE} \
    --build-arg DRIVER_VER=${DRIVER_VER} \
    --build-arg DRIVER_SRC=${DRIVER_SRC} \
    --build-arg KERNEL_VERSION=${KERNEL_VER} \
    --build-arg CUSTOM_KERNEL=${CUSTOM_KERNEL} \
    -t ${REGISTRY}/${DRIVER_IMAGE}:${TAG}

}
push_image () {
  podman push --tls-verify=false ${REGISTRY}/${DRIVER_IMAGE}:${TAG}
  exit_on_error $?
  rm -rf ${TEMP_DIR}

}

generate_machine_config () {

  local service=$(base64 -w 0 service.sh)
  local ptp_config=$(base64 -w 0 ptp-config.sh)

cat <<- END_OF_MACHINE_CONFIG > mc-oot-ice.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 10-oot-ice
spec:
  config:
    ignition:
     version: 3.2.0
    storage:
      files:
        - contents:
            source: 'data:text/plain;charset=us-ascii;base64,$service'
          filesystem: root
          mode: 493
          path: /usr/local/bin/oot-ice
        - contents:
            source: 'data:text/plain;charset=us-ascii;base64,$ptp_config'
          filesystem: root
          mode: 493
          path: /usr/local/bin/ptp-config
    systemd:
      units:
      - contents: |
          [Unit]
          Description=out-of-tree driver loader
          Wants=network-online.target
          After=network-online.target
          # Before kubelet.service (no effect on systems without kubernetes)
          Before=kubelet.service

          [Service]
          Type=oneshot
          RemainAfterExit=true
          # Use bash to workaround https://github.com/coreos/rpm-ostree/issues/1936
          ExecStart=/usr/bin/bash -c "/usr/local/bin/oot-ice load  ${REGISTRY}/${DRIVER_IMAGE}:${TAG}"
          ExecStop=/usr/bin/bash -c "/usr/local/bin/oot-ice unload ${REGISTRY}/${DRIVER_IMAGE}:${TAG}"
          ExecStartPost=/usr/bin/bash -c "/usr/local/bin/ptp-config"
          StandardOutput=journal+console

          [Install]
          WantedBy=default.target
        enabled: true
        name: "oot-ice.service"
  kernelArguments:
    - firmware_class.path=/var/lib/firmware
END_OF_MACHINE_CONFIG
}

# Default values
CUSTOM_KERNEL=""
APPLY_PATCHES="no"
KERNEL_VER=""
BUILD_RT="yes"
OCP_VER=""
KUBECONFIG=${KUBECONFIG:-""}

REGISTRY=${REGISTRY:-""}
if [ -z ${REGISTRY} ]; then
   echo "The environment variable REGISTRY must be set."
   exit 1
fi

while getopts hrc:k:o:p ARG ; do
  case $ARG in
    o ) OCP_VER=$OPTARG ;;
    r ) BUILD_RT="yes" ;;
    c ) CUSTOM_KERNEL=$OPTARG ;;
    k ) KERNEL_VER=$OPTARG ;;
    p ) APPLY_PATCHES="yes" ;;
    h ) print_usage ; exit 0 ;;
    ? ) print_usage ; exit 1 ;;
  esac
done
shift $(($OPTIND - 1))

if [ $# -lt 1 ]; then
  print_usage
  exit 1
fi

DRIVER_VER=$1; shift

# Try to get the OCP version from the cluster in KUBECONFIG
if [ -z ${OCP_VER} ]; then
  if [ -z ${KUBECONFIG} ]; then
    echo "Please specify -o or properly set your KUBECONFIG env variable"
    exit 1
  fi
  OCP_VER=$(oc get clusterversions/version -o json  | jq -r ".status.desired.version")
  exit_on_error $?
fi


DRIVER_IMAGE="oot-ice-${DRIVER_VER}"
MINOR_VER=$(echo "$OCP_VER" | cut -f2 -d.)
TAG=${OCP_VER}

if [ ! -z ${KERNEL_VER} ]; then
  # validate that the custom kernel rpm is here
  if [ ! -f ${CUSTOM_KERNEL} ]; then
    echo "Custom kernel rpm \"${CUSTOM_KERNEL}\" not found"
    exit 1
  fi


elif [[  "$MINOR_VER" -le 12 ]]; then # Building for an OCP release 4.12 <=. image name is changed as well as labels
  MACHINE_OS=$(oc adm release info --image-for=machine-os-content quay.io/openshift-release-dev/ocp-release:${OCP_VER}-x86_64)
  BASE_IMAGE='registry.access.redhat.com/ubi8:latest'
  if [ ${BUILD_RT} == "yes" ]; then
    KERNEL_VER=$(oc image info -o json ${MACHINE_OS}  | jq -r ".config.config.Labels[\"com.coreos.rpm.kernel-rt-core\"]")
    TAG="${OCP_VER}-rt"
  else
    KERNEL_VER=$(oc image info -o json ${MACHINE_OS}  | jq -r ".config.config.Labels[\"com.coreos.rpm.kernel\"]")
  fi
else # rhel9 based
  MACHINE_OS=$(oc adm release info --image-for=rhel-coreos quay.io/openshift-release-dev/ocp-release:${OCP_VER}-x86_64)
  BASE_IMAGE='registry.access.redhat.com/ubi9:latest'
  if [ ! -z ${KERNEL_VER} ]; then
    GET_DEVEL_RPM="yes"
  elif [ ${BUILD_RT} == "yes" ]; then
    KERNEL_VER=$(oc image info -o json ${MACHINE_OS}  | jq -r ".config.config.Labels[\"ostree.linux\"]")
    KERNEL_VER="${KERNEL_VER}+rt"
    # cant use a + sign in container image tag
    TAG="${OCP_VER}-rt"
  else
    KERNEL_VER=$(oc image info -o json ${MACHINE_OS}  | jq -r ".config.config.Labels[\"ostree.linux\"]")
  fi
fi

build_image

generate_machine_config

push_image
