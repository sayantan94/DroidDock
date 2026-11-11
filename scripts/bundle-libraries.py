"""Bundle Homebrew dylibs without leaving dependencies on this development Mac."""
import pathlib
import shutil
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
frameworks = app / 'Contents/Frameworks'
resources = app / 'Contents/Resources'
binary = app / 'Contents/MacOS/MacDroid'
seen = set()

def dependencies(path):
    output = subprocess.check_output(['otool', '-L', str(path)], text=True)
    return [line.strip().split(' (')[0] for line in output.splitlines()[1:]]

def bundle(path):
    for dependency in dependencies(path):
        if not dependency.startswith(('/opt/homebrew/', '/usr/local/')):
            continue
        source = pathlib.Path(dependency)
        target = frameworks / source.name
        if source.name not in seen:
            seen.add(source.name)
            shutil.copy2(source, target)
            target.chmod(0o755)
            subprocess.run(['install_name_tool', '-id', '@rpath/' + source.name, str(target)], check=True)
            bundle(target)
        replacement = ('@executable_path/../Frameworks/' if path == binary else '@loader_path/') + source.name
        subprocess.run(['install_name_tool', '-change', dependency, replacement, str(path)], check=True)

bundle(binary)
for formula in ['libmtp', 'libusb']:
    prefix = pathlib.Path(subprocess.check_output(['brew', '--prefix', formula], text=True).strip())
    shutil.copy2(prefix / 'COPYING', resources / (formula + '-COPYING.txt'))
for path in [binary, *frameworks.glob('*.dylib')]:
    remaining = [dep for dep in dependencies(path) if dep.startswith(('/opt/homebrew/', '/usr/local/'))]
    if remaining:
        raise RuntimeError(f'Unbundled dependencies in {path}: {remaining}')
