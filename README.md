# secureblue, sealed

An experiment in getting [secureblue](https://github.com/secureblue/secureblue/)
to boot from a UKI via systemd-boot,
with bootc's composefs native backend providing fs-verity.

![Terminal showing `run0 bootc status` output with verity](./screenshot-qemu.png)

Note: "sealed" is a slight misnomer, since the UKI and systemd-boot are not
Secure Boot signed to keep the focus on the rest of the setup.

The result, when combined with TPM measured boot, is a substantially more secure
boot chain than secureblue's GRUB flow.

Ideally, the sealed image will be made by upstream and boot-time installers like
Anaconda will have an option to use the `--composefs-backend` flag for their
`bootc install` command.
Also, the bugs in bootc, possibly podman, and systemd-boot would be fixed.
It would be even better if `systemd-boot` wasn't used, and changes to boot order
needed for updates were done by changing the UEFI boot order directly.

The purpose of this experiment is to provide a bootable environment in which
userspace issues (e.g. scripts relying on ostree) can be fixed ahead of the
ideal becoming reality.

## Instructions & Design

The following image-related environment variables can optionally be set:

- `BOOTC_IMG`: An image that provides `skopeo` and `bootc` CLIs.
  Default: `quay.io/fedora/fedora-bootc:43`.
- `UPSTREAM_IMG`: The secureblue image to work from.
  Default: `ghcr.io/secureblue/silverblue-main-hardened:43`.
- `BASE_IMG`: The name for the locally built image that will have the necessary
  edits made to the upstream image to work with this setup.
  Default: `localhost/silverblue-main-hardened-bootc:43`.
- `SEALED_IMG`: The name for the locally built image that has the UKI embedded
  and will be the one ultimately used for installs.
  Default: `localhost/silverblue-main-hardened-sealed:43`.

1. Execute `./build.sh`.

   This script uses `Containerfile.base` to add the systemd-boot binaries
   and the bootc dracut module to the upstream secureblue image.

   When booting the VM/disk, GNOME's initial setup will prompt to make a user;
   for testing, one can uncomment the relevant line in `Containerfile.base`
   to set a temporary password for the root user instead.

   This script then uses `digest.sh` to compute the composefs digest of the base
   image. Since this takes some time, when testing changes to these scripts one
   can skip re-calculating the digest by setting the `CFS_DIGEST` environment
   variable. This is written to `./digest-for-reference.txt` for ease of
   reference.

   Due to a
   [bug](https://github.com/bootc-dev/bootc/issues/1703#issuecomment-3562107282),
   `digest.sh` needs to decompress the layers of the base image.
   Since this takes some time, one can skip redoing this work if the base image
   hasn't changed on subsequent runs by setting the `SKIP_DECOMPRESS=1`
   environment variable.

   Finally, it builds the sealed image with the calculated digest.

2. Execute `./to-disk-img.sh` to make a raw disk image for use as a VM,
   or `./to-disk.sh` to wipe & install on a block device.

   This requires the use of `run0`, so there will be prompts for authentication
   several times throughout, to copy the sealed image from the regular user's
   podman to rootful podman and then to install it.

   Due to the aforementioned
   [bug](https://github.com/bootc-dev/bootc/issues/1703#issuecomment-3562107282),
   copying the sealed image needs to decompress the layers.

   These environment variables control behaviour:

   - `DISK_IMG`: the raw disk image file to write to.
     Default: `./bootable.img`.
   - `DISK`: the block device to write to.
     Default: `/dev/sda`.
   - `SKIP_COPY_TO_ROOTFUL=1`: on subsequent runs, this can be skipped
     if the sealed image hasn't changed to save time.

   If a raw disk image was made, execute `./run-vm.sh` to run it via QEMU
   (can take a while for gnome initial setup to appear).

3. To check that it worked, execute `run0 bootc status` inside the system,
   and one should see the computed digest from earlier listed after "Verity: ".

4. To be able to upgrade using the live system's own containers-storage
   instead of a "remote" repo at localhost:80,
   clone this repo on the live system, edit `/etc/containers/policy.json`
   to allow `containers-storage` and `oci-archive` transports as well as
   `ghcr.io` and `quay.io` under the `docker` transport
   with `"type": "insecureAcceptAnything"`,
   then run the `./build.sh` script,
   then `./first-local-upgrade.sh`.

   Now, check `run0 bootc status` to see the local image is "staged",
   and if one has Secure Boot disabled on real hardware also
   edit `/boot/loader/entries.staged/` to have the correct `options`
   per [below section](#errors-that-might-be-due-to-secure-boot-being-disabled);
   note that the verity for the new entry (`*-1.conf`) will be different
   from the old entry, matching the new `.efi` filename.

   Finally, reboot and pick the top option in systemd-boot's menu (`*-1.conf`).
   Verify this worked by checking `run0 bootc status` and seeing both
   "Booted image" and "Rollback image" with the right verities and timestamps.

   This has switched bootc from using a remote registry to using your local
   rootful  containers-storage, so any future use of `run0 bootc upgrade` will 
   check there for any updates to the image, no remote registry needed
   (useful for experimenting with this setup).

# TODO

- Fix DNS not working out of the box.
	- `dnsconfd.service` failing.
	- Note that manually doing `ujust dns-selector` fixes DNS.
- Fix/investigate `bootloader-update.service` failing. Error is:
  ```
  bootupctl[1033]: error: get parent devices: get parent devices from mount point boot or sysroot: While looking for backing devices of systemd-1: Subprocess failed: ExitStatus(unix_wait_status(8192))
  bootupctl[1033]: lsblk: systemd-1: not a block device
  ```
- Fix/investigate `securebluecleanup.service` and
  `secureblue-flatpak-setup.service` failing.

  No logs in `systemctl status`, just `code=exited, status=1/FAILURE`
- `/usr/etc/` does not exist, but `/etc/` does and is populated correctly.
  However, this breaks podman's `/etc/containers/policy.json`
  since secureblue hardcodes the `keyPath`s to `/usr/etc/pki/containers/...`.

  This is a bug in bootc, file an issue if it does not exist, since the
  [docs](https://github.com/bootc-dev/bootc/blob/d5c6515e237d7e8b9b1e385fbc393e8c517eafad/docs/src/filesystem.md?plain=1#L107-L112)
  say "Do *not* explicitly put files into this location, it can create undefined behavior"
  so we can't copy `/etc/` to `/usr/etc/` ourselves in `./Containerfile.sealed`.
- Fix `firewalld.service` sometimes failing.
  Error was:
  ```
  firewalld.service: start opteration timed out. Terminating.
  firewalld.service: Failed with result 'timeout'.
  ```
  Only occured after rebooting after running `./first-local-upgrade.sh`,
  another reboot after and it was fine again...
- `run0 setenforce 1` breaks everything, hence why `enforcing=0`
  is added to kernel cmdline in `./Containerfile.sealed` until this is fixed.

  `journalctl -b` shows several:
  ```
  audit[...] AVC avc: denied { read } for pid=... comm="pkla-check-auth" path="/48/..." dev="sda3" ino=44664 scontext=system_u:system_r:policykit_auth_t:s0 tcontext=system_u:object_r:unlabeled_t:s0 tclass=file permissive=0
  polkitd[1077] Error evaluating admin rules: Error: Helper exited with non-zero exit status 127, stdout=`', stderr=`/usr/bin/pkla-check-authorization: error while loading shared libraries: /lib64/libc.so.6: cannot apply additional memory protection after relocation: Permission denied
  ```

  Upstream are aware of this bug in bootc/composefs-fs,
  see https://github.com/bootc-dev/bootc/issues/1826
- Figure out how `ujust set-kargs-hardening` will make UKI addons to edit the UKI
  cmdline per additional options at https://secureblue.dev/articles/kargs
- `ujust audit-secureblue` many errors but does still finish and provide some
  recommendations.
- Compare with normal installation to check all customisations are applied properly,
  and all `ujust` stuff works.
- Check journal for any other errors.

## Errors Specific to Real Hardware Install via `./to-disk.sh`

- `plymouth-quit-wait.service` takes ~1min on first boot, subsequent ~18s.
- All `*.device` take ~9s on first boot,
  but ~40s on subsequent boots for _most_ e.g.
  `sys-devices-virtual-block-loop0.device`, but not all (some still take ~9s).
  
  The ~40s only sometimes happens... some boots they all take ~9s.
- `unbound-anchor.service` takes ~12s on every boot.
- `run0 bootc status` errors with:
  ```
  error: Status: Getting composefs deployment status: Getting composefs deployment status: Opening user.cfg: No such file or directory (os error 2)
  ```
  when booting directly from the UKI in `/EFI/Linux/bootc/`
  or from systemd-boot's auto-detected UKI if it's copied to `/EFI/Linux/`,
  but works properly when booting from corrected entry w/ options
  (see [below section](#errors-that-might-be-due-to-secure-boot-being-disabled)).

  This is because the EFI variable checked
  [here](https://github.com/bootc-dev/bootc/blob/315bfb3cfd52ff169a03422cde1dfa2869c6b1c9/crates/lib/src/bootc_composefs/status.rs#L220)
  does not get set...
  bootc also needs to check `StubInfo-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f`
  to detect that systemd-stub is being used, maybe?
  Depends on if that still contains "systemd" somewhere in it
  when GRUB(+UKI) is used...
  This should be filed as a bug with `bootc status` if it does not already exist,
  as it needs to handle direct-from-UKI & systemd-boot's auto-detected UKIs
  separately from GRUB and systemd-boot
  (i.e. condition is LoaderInfo not set but StubInfo contains "systemd-stub").

## Errors that Might be Due to Secure Boot being Disabled

- Cannot boot from `/EFI/BOOT/BOOTX64.EFI` or `/EFI/systemd/systemd-bootx64.efi`
  (blank screen, fans pick up for a while, then device powers off),
  but can boot from UKI in `/EFI/Linux/bootc/` though it takes 2+ minutes :/

  Can see systemd-boot menu if setting `timeout menu-force` in
  `/boot/loader/loader.conf` with an entry for the UKI, but selecting it still
  leads to a power off.

  Copying the UKI from `/EFI/Linux/bootc/` to `/EFI/Linux/` allows systemd-boot
  to auto-detect it, and this boot entry does work from the systemd-boot menu.
  Pressing `p` in the systemd-boot menu shows systemd-boot sees the cmdline
  for the auto-detected entry, but not for the `/boot/loader/entries/` entry.

  Editing `/boot/loader/entries/` entry with `options ...` from `/proc/cmdline`
  works.
  This might be because
  "When Secure Boot is not active, the options passed via the command line override the embedded .cmdline"
  per [arch wiki](https://wiki.archlinux.org/title/Systemd-boot#Unified_kernel_images:~:text=When%20Secure%20Boot%20is%20not%20active),
  i.e. systemd-boot is passing an empty command line which overrides embedded.
  File a bug with systemd-boot if it doesn't already exist?

# References

https://gitlab.com/fedora/bootc/docs/-/raw/e046a20da7dc6d211d049b00902b24d2619dccc0/modules/ROOT/pages/experimental-building-sealed.adoc

https://github.com/gerblesh/arch-bootc/tree/composefs-uki

https://github.com/bootc-dev/bootc/blob/e074a41720c7dc9c95ec6d1308ddf884cb91b240/Dockerfile.cfsuki

https://github.com/bootc-dev/bootc/blob/e074a41720c7dc9c95ec6d1308ddf884cb91b240/hack/build-sealed

# Licenses

- `./Containerfile.sealed` is covered by `./LICENSE-CC-BY-SA-3.0`,
  since only minor modifications have been made.

Any snippets copied from elsewhere are considered too small and/or general,
so everything else falls under `./LICENSE` aka `./UNLICENSE`.

