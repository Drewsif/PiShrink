# PiShrink GitHub Action

GitHub action to run [PiShrink](https://github.com/Drewsif/PiShrink) on a Raspberry Pi SD card image.

## Basic Usage Examples

Note: in the below example sequences of GitHub Actions job steps, the URL of the downloaded image
doesn't actually exist! Normally, you would generate an image file by some other method, e.g.
downloading a base image, expanding it, and modifying its filesystem (e.g. with
[Pimod](https://github.com/Nature40/pimod), as in [a below example](#pimod-usage-example)).

### Shrink with gzip

```
- name: Download an example image
  run: wget http://some-website.com/large-rpi-sd-card-image.img

- name: Shrink image
  uses: ethanjli/pishrink-action@v0.1.0
  with:
    image: large-rpi-sd-card-image.img
    compress: gzip
    compress-parallel: true

- name: Upload image to Job Artifacts
  uses: actions/upload-artifact@v4
  with:
    name: shrunken-image
    path: large-rpi-sd-card-image.img
    if-no-files-found: error
    overwrite: true
```

### Shrink with xz

```
- name: Download an example image
  run: wget http://some-website.com/large-rpi-sd-card-image.img

- name: Shrink image
  uses: ethanjli/pishrink-action@v0.1.0
  with:
    image: large-rpi-sd-card-image.img
    compress: xz
    compress-parallel: true

- name: Upload image to Job Artifacts
  uses: actions/upload-artifact@v4
  with:
    name: shrunken-image
    path: large-rpi-sd-card-image.img
    if-no-files-found: error
    overwrite: true
```

### Separate destination

```
- name: Download an example image
  run: wget http://some-website.com/large-rpi-sd-card-image.img

- name: Shrink image
  uses: ethanjli/pishrink-action@v0.1.0
  with:
    image: large-rpi-sd-card-image.img
    destination: result.img.gz
    compress: gzip
    compress-parallel: true

- name: Upload image to Job Artifacts
  uses: actions/upload-artifact@v4
  with:
    name: shrunken-image
    path: result.img.gz
    if-no-files-found: error
    compression-level: 0
    overwrite: true
```

### Automatically-determined destination

```
- name: Download an example image
  run: wget http://some-website.com/large-rpi-sd-card-image.img

- name: Shrink image
  id: shrink-image
  uses: ethanjli/pishrink-action@v0.1.0
  with:
    image: large-rpi-sd-card-image.img
    compress: gzip
    compress-parallel: true

- name: Upload image to Job Artifacts
  uses: actions/upload-artifact@v4
  with:
    name: shrunken-image
    path: ${{ steps.shrink-image.outputs.destination }} # this is large-rpi-sd-card-image.img.gz
    if-no-files-found: error
    compression-level: 0
    overwrite: true
```

## Pimod Usage Example

This example job uses Pimod to generate a custom image, and then shrinks it before uploading as an
artifact on the GitHub Actions job:

```
jobs:
  build:
    name: Build image
    runs-on: ubuntu-latest
    steps:
      - name: Make a Pifile for Pimod
        uses: 1arp/create-a-file-action@0.4.5
        with:
          path: cowsay.Pifile
          content: |
            FROM https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-03-15/2024-03-15-raspios-bookworm-arm64-lite.img.xz
            TO cowsay-image.img
            PUMP 8G

            # Install and test out cowsay:
            RUN apt-get update
            RUN apt-get install -y cowsay
            echo "I'm running in a chroot!" | cowsay

      - name: Build the image
        uses: Nature40/pimod@master
        with:
          pifile: cowsay.Pifile

      - name: Shrink the image
        uses: ethanjli/pishrink-action@v0.1.0
        with:
          image: cowsay-image.img
          compress: gzip
          compress-parallel: true

      - name: Upload image to Job Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: cowsay-image
          path: cowsay-image.img.gz
          if-no-files-found: error
          retention-days: 0
          compression-level: 0
          overwrite: true
```

## Usage Options

Inputs:

| Input                | Allowed values       | Required?            | Description                                                                           |
|----------------------|----------------------|----------------------|---------------------------------------------------------------------------------------|
| `image`              | file path            | yes                  | Path of the image to shrink.                                                          |
| `destination`        | file path            | no                   | Path to write the shrunken image to.                                                  |
| `compress`           | `gzip`, `xz`, `none` | no (default `none`)  | Compress the image after shrinking it.                                                |
| `compress-parallel`  | `true`, `false`      | no (default `false`) | Compress the image in parallel using multiple cores.                                  |
| `prevent-expansion`  | `true`, `false`      | no (default `false`) | Prevent automatic filesystem expansion when the image is booted for the first time.   |
| `advanced-fs-repair` | `true`, `false`      | no (default `false`) | Attempt to repair the filesystem using additional options if the normal repair fails. |
| `verbose`            | `true`, `false`      | no (default `false`) | Enable more verbose output                                                            |

Outputs:

- `destination` is the path of the shrunken image produced by pishrink.
  If it was compressed with gzip or xz, this path will include `.gz` or `.xz` (respectively) as its
  file extension.

## Credits

This repository uses the `pishrink.sh` script provided by
[Drewsif/PiShrink](https://github.com/Drewsif/PiShrink), published under the MIT License; this
repository is also released under the MIT License.
