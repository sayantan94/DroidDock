"""Package the exact upstream sources and Homebrew recipes for bundled LGPL libs."""
import hashlib
import pathlib
import re
import subprocess
import tempfile
import urllib.request
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
output = root / 'dist' / 'DroidDock-USB-library-sources.zip'
output.parent.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory() as temporary, zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for formula in ['libmtp', 'libusb']:
        prefix = pathlib.Path(subprocess.check_output(['brew', '--prefix', formula], text=True).strip()).resolve()
        recipe = prefix / '.brew' / (formula + '.rb')
        text = recipe.read_text()
        url = re.search(r'^  url "([^"]+)"', text, re.MULTILINE).group(1)
        expected = re.search(r'^  sha256 "([a-f0-9]+)"', text, re.MULTILINE).group(1)
        filename = url.rsplit('/', 1)[1]
        target = pathlib.Path(temporary) / filename
        subprocess.run(['curl', '--fail', '--location', '--retry', '3', '--output', str(target), url], check=True)
        if hashlib.sha256(target.read_bytes()).hexdigest() != expected:
            raise RuntimeError('Upstream source checksum mismatch: ' + formula)
        archive.write(target, filename)
        archive.write(recipe, formula + '.rb')
        archive.writestr(formula + '-source.txt', f'Version: {prefix.name}\nSource: {url}\nSHA256: {expected}\n')
    archive.writestr('README.txt', 'Corresponding source for the unmodified USB libraries bundled with DroidDock.\n'
        'Extract each upstream archive and follow its build instructions. The included Homebrew recipes record build options.\n'
        'Use the same CPU architecture as DroidDock. Replace dylibs in DroidDock.app/Contents/Frameworks,\n'
        'adjust install paths to @loader_path, then re-sign locally: codesign --force --deep --sign - DroidDock.app\n')
print(output)
