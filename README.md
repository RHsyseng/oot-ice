# oot-ice

This is a repo to build Out Of Tree Intel ice driver and load it on a OCP cluster

It builds the driver inside the Driver Toolkit image and pushes an image containing the kernel module to a registry.

### Prereq
- Set `REGISTRY` in your env.  This is the registry the driver container will be pushed to and that the OCP cluster will pull the driver container from.
  In this sense, your default pull secret should be able to allow you to push to this registry on the build machine.
  Your cluster should also have the pull secret of this registry so that it can pull images from this registry.
- Set `KUBECONFIG` in your env.
  The OCP version of your `KUBECONFIG` cluster will be used to build the driver and it will be used to apply the generated MachineConfig



### Build
The script supports building the ice driver against different kernels.

To build against the standard kernel of the OCP version of the cluster in `KUBECONFIG`
```bash
./oot-ice.sh <ice-driver-version>
```

To build against the real time kernel of the OCP version of the cluster in `KUBECONFIG`
```bash
./oot-ice.sh -r <ice-driver-version>
```

To build against the standard kernel of a specific OCP version.
```bash
./oot-ice.sh -o <ocp_version> <ice-driver-version>
```

To build against the real time kernel of a specific OCP version.
```bash
./oot-ice.sh -r -o <ocp_version> <ice-driver-version>
```

To build against a custom kernel's supplied devel package.
The kernel-devel package file must be in the current directory.
```bash
./oot-ice.sh -c <custom_kernel_devel_rpm> -k <kernel_version> <ice-driver-version>
```

To apply patches, use the -p option. All the patches found under the requested driver's folder will be applied.

```bash
./oot-ice.sh -p <ice-driver-version>
```

### Deploy

Once the build finishes successfully, a `MachineConfig` to deploy the driver container to the cluster is generated.
We can now apply this `MachineConfig` to deploy the driver.

```bash
oc apply -f mc-oot-ice.yaml
```
