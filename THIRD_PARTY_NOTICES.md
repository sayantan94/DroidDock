# Third-party components

DroidDock dynamically links libmtp and libusb. The packaged app includes their
license texts in Contents/Resources. These libraries are unmodified Homebrew
builds; their dylib install paths are adjusted for a self-contained app bundle.

- **libmtp 1.1.23**, LGPL 2.1 or later. Source: https://github.com/libmtp/libmtp/tree/libmtp-1-1-23
- **libusb**, LGPL 2.1 or later. Source: https://github.com/libusb/libusb

The build uses the locally installed libusb version. Run `brew list --versions
libusb` to identify it. Rebuild a compatible replacement library from its source,
replace the corresponding file in Contents/Frameworks, then re-sign locally with
`codesign --force --deep --sign - DroidDock.app`. No library is statically linked.

Apple frameworks are provided by macOS. DroidDock has no relationship to the
commercial MacDroid app; that app is not included, modified, or replaced.

## Windows

The Windows app uses [MediaDevices 2.0.0](https://github.com/Bassman2/MediaDevices)
under the MIT license, reproduced below. It communicates with Windows Portable
Devices (WPD) provided by Windows. The self-contained build includes Microsoft's
[.NET runtime](https://github.com/dotnet/runtime) and
[WPF](https://github.com/dotnet/wpf), distributed under the MIT license; their
runtime license and third-party notices are copied from the SDK's resolved
runtime packages into the published output's `licenses` directory.

### MediaDevices license

MIT License

Copyright (c) 2017 - 2023 Ralf Beckers

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
