"""同一完整Verilog测试台的Windows原生编译执行，不删断言或栅格输出。"""
from pathlib import Path
import os
import re
import subprocess


def run_compiled(root, output, name, top, files, command):
    vroot = root/'build/raw_video/tools/verilator_py/verilator'
    cxx = Path('D:/minGW64/mingw64/bin/g++.exe')
    obj = output/('compiled_'+name)
    obj.mkdir(exist_ok=True)
    env = os.environ.copy()
    env['VERILATOR_ROOT'] = vroot.as_posix()
    env['PATH'] = str(cxx.parent)+os.pathsep+env['PATH']

    def invoke(args, suffix, timeout):
        with (output/(name+suffix+'.log')).open('wb') as log:
            result = subprocess.run(args, cwd=output, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode:
            text = (output/(name+suffix+'.log')).read_text(encoding='utf-8', errors='replace')
            raise RuntimeError(name+suffix+': '+text[-5000:])

    # Icarus的-s仅用于选顶层；输入列表、宏、测试台参数保持原意。
    translated = []
    skip = False
    include_next = False
    for arg in files:
        if include_next:
            translated.append('-I'+arg)
            include_next = False
            continue
        if skip:
            skip = False
            continue
        if arg == '-s':
            skip = True
        elif arg == '-I':
            include_next = True
        elif arg.startswith('-P'+top+'.'):
            translated.append('-G'+arg[len(top)+3:])
        else:
            translated.append(arg)
    invoke([str(vroot/'bin/verilator_bin.exe'), '--cc', '--main', '--timing', '--assert',
            '-Wno-fatal', '--top-module', top, '--Mdir', str(obj),
            '-I'+str(output), '-I'+str(root/'sim'), *translated], '_generate', 180)
    main = obj/('V'+top+'__main.cpp')
    source = main.read_text(encoding='utf-8')
    source, count = re.subn(r'(int main\([^\n]+\) \{)',
                           r'\1\n    std::setvbuf(stdout, nullptr, _IONBF, 0);', source, count=1)
    if count != 1:
        raise RuntimeError('Verilator main入口不匹配')
    main.write_text('#include <cstdio>\n'+source, encoding='utf-8', newline='\n')
    inc = vroot/'include'
    exe = obj/(name+'.exe')
    invoke([str(cxx), '-std=c++20', '-O2', '-pthread', '-DVL_TIME_CONTEXT',
            '-I'+str(inc), '-I'+str(inc/'vltstd'), '-I'+str(obj),
            *[str(p) for p in sorted(obj.glob('*.cpp'))],
            *[str(inc/n) for n in ('verilated.cpp','verilated_timing.cpp','verilated_threads.cpp')],
            '-o', str(exe)], '_compile', 600)
    return command([str(exe)], name)
