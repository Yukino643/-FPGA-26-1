#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sync_to_sd.py — SD 卡一键安全同步工具（防物理残留死锁版）
基于官方 lab_ex5 的 sync_to_sd.py 改进，支持 BMP + WAV。

用法:
  python sync_to_sd.py E:                    # 同步 output_bmp 目录
  python sync_to_sd.py E: -s my_images -n 4  # 指定源目录和数量
"""
import os
import sys
import glob
import shutil
import argparse


def corrupt_old_bmp_headers(target_drive):
    """破坏旧 BMP 的 BM 魔数，防止 FPGA 物理扇区扫描读到残留数据"""
    print(f"扫描 {target_drive}，清除旧 BMP 识别头...")
    bmp_files = glob.glob(os.path.join(target_drive, "*.bmp"))
    count = 0
    for f in bmp_files:
        try:
            with open(f, 'r+b') as fp:
                if fp.read(2) == b'BM':
                    fp.seek(0)
                    fp.write(b'XX')
                    count += 1
        except Exception as e:
            print(f"  [警告] 无法处理 {f}: {e}")
    print(f"已破坏 {count} 个旧 BMP 头。")


def corrupt_old_wav_headers(target_drive):
    """破坏旧 WAV 的 RIFF 魔数"""
    print(f"扫描 {target_drive}，清除旧 WAV 识别头...")
    wav_files = glob.glob(os.path.join(target_drive, "*.wav"))
    count = 0
    for f in wav_files:
        try:
            with open(f, 'r+b') as fp:
                if fp.read(4) == b'RIFF':
                    fp.seek(0)
                    fp.write(b'XXXX')
                    count += 1
        except Exception as e:
            print(f"  [警告] 无法处理 {f}: {e}")
    print(f"已破坏 {count} 个旧 WAV 头。")


def clean_drive(target_drive):
    """删除目标驱动器下的所有可见文件"""
    print(f"清空 {target_drive}...")
    for item in os.listdir(target_drive):
        path = os.path.join(target_drive, item)
        if item.startswith('.'):
            continue
        try:
            if os.path.isfile(path):
                os.remove(path)
            elif os.path.isdir(path):
                shutil.rmtree(path)
        except Exception as e:
            print(f"  [警告] 无法删除 {path}: {e}")
    print("清空完毕。")


def sync_files(source_dir, target_drive, max_count=8):
    """从源目录同步 BMP 和 WAV 文件到目标驱动器"""
    if not os.path.exists(source_dir):
        print(f"[错误] 源目录不存在: {source_dir}")
        return

    # 收集 BMP 和 WAV
    bmp_files = sorted(glob.glob(os.path.join(source_dir, "*.bmp")))
    wav_files = sorted(glob.glob(os.path.join(source_dir, "*.wav")))

    if not bmp_files and not wav_files:
        print(f"[错误] {source_dir} 中没有 BMP 或 WAV 文件")
        return

    print(f"找到 {len(bmp_files)} 个 BMP, {len(wav_files)} 个 WAV")

    # 同步 BMP（限制数量）
    for i, f in enumerate(bmp_files[:max_count]):
        name = f"{i:02d}_{os.path.basename(f)}"
        try:
            shutil.copy2(f, os.path.join(target_drive, name))
            print(f"  [同步] {os.path.basename(f)} -> {name}")
        except Exception as e:
            print(f"  [失败] {f}: {e}")

    # 同步 WAV
    for i, f in enumerate(wav_files):
        name = f"{i:02d}_{os.path.basename(f)}"
        try:
            shutil.copy2(f, os.path.join(target_drive, name))
            print(f"  [同步] {os.path.basename(f)} -> {name}")
        except Exception as e:
            print(f"  [失败] {f}: {e}")

    print("同步完成。安全弹出后插入 FPGA 开发板。")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FPGA SD 卡同步工具（防物理残留死锁）")
    parser.add_argument('drive', help='SD 卡盘符 (如 E:)')
    parser.add_argument('-s', '--source', default=None, help='源文件夹 (默认: output_bmp)')
    parser.add_argument('-n', '--num', type=int, default=8, help='最大 BMP 数量 (默认: 8)')
    args = parser.parse_args()

    target = args.drive
    if not target.endswith((':\\', ':/')):
        target += '\\' if not target.endswith(':') else '\\'

    if not os.path.exists(target):
        print(f"[错误] 找不到驱动器: {target}")
        sys.exit(1)

    if target.upper().startswith('C:'):
        confirm = input("警告: 目标是系统盘 C:！确定继续？(y/N): ")
        if confirm.lower() != 'y':
            sys.exit(0)

    source = args.source or os.path.join(os.path.dirname(os.path.abspath(__file__)), "output_bmp")

    print("=" * 50)
    print(f"目标: {target}")
    print(f"源:   {source}")
    print("=" * 50)

    corrupt_old_bmp_headers(target)
    corrupt_old_wav_headers(target)
    clean_drive(target)
    sync_files(source, target, args.num)
