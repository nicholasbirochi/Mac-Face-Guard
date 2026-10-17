#!/usr/bin/env python3
"""Convert reviewed local EdgeFace inputs. No network, camera or owner templates."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time

WEIGHTS = '5ae7504cd9aee0a5d52c2115fd2eb66b0985dd1730f40134b5854e0cb658ce16'
SOURCE = {
    '__init__.py': 'f5b480e7bfa19214cc27b5fa092d2948dda444c9c3ea9edec726c02ea1f7884a',
    'timmfr.py': '5f2cec2f38c7f9c320abf12df86d7f46727e08c24e678cf668345473e5a40f12',
}


def package_digest(path):
    digest = hashlib.sha256()
    for item in sorted(p for p in path.rglob('*') if p.is_file()):
        assert not item.is_symlink()
        digest.update(item.relative_to(path).as_posix().encode() + b'\0')
        digest.update(hashlib.sha256(item.read_bytes()).digest())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; preserve it or choose a new path.')
    assert hashlib.sha256(args.checkpoint.read_bytes()).hexdigest() == WEIGHTS
    for name, expected in SOURCE.items():
        assert hashlib.sha256((args.source / 'backbones' / name).read_bytes()).hexdigest() == expected
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['TIMM_FUSED_ATTN'] = '0'
    sys.path.insert(0, str(args.source.resolve()))
    import coremltools as ct
    import numpy as np
    from PIL import Image
    import torch
    from backbones import get_model

    torch.set_num_threads(2)
    torch.manual_seed(7)
    model = get_model('edgeface_xs_gamma_06')
    model.load_state_dict(torch.load(args.checkpoint, map_location='cpu', weights_only=True), strict=True)
    model.eval()
    with torch.no_grad():
        traced = torch.jit.trace(model, torch.zeros(1, 3, 112, 112))
    converted = ct.convert(traced,
        inputs=[ct.ImageType(name='face', shape=(1, 3, 112, 112),
            scale=1 / 127.5, bias=[-1, -1, -1], color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name='embedding')],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT32,
        compute_units=ct.ComputeUnit.CPU_ONLY)
    converted.short_description = 'EdgeFace XS gamma 0.6; local experimental identity embeddings; no PAD.'
    converted.license = 'Upstream repository BSD-3-Clause; see upstream LICENSE. Weights not redistributed by MacFaceGuard.'
    converted.user_defined_metadata['source_revision'] = 'ce86851cfc37979a9cd2558598d0e9bc592cbba3'
    converted.user_defined_metadata['weights_sha256'] = WEIGHTS
    converted.save(str(args.output))

    # Synthetic RGB inputs exercise conversion and normalization, not biometric accuracy.
    rng = np.random.default_rng(7)
    inputs = [np.zeros((112, 112, 3), dtype=np.uint8),
              np.full((112, 112, 3), 255, dtype=np.uint8)]
    inputs += [rng.integers(0, 256, (112, 112, 3), dtype=np.uint8) for _ in range(6)]
    results = []
    for rgb in inputs:
        tensor = torch.from_numpy(rgb.transpose(2, 0, 1).copy()).float().unsqueeze(0) / 127.5 - 1
        with torch.no_grad():
            expected = model(tensor).numpy().reshape(-1)
        started = time.perf_counter()
        actual = converted.predict({'face': Image.fromarray(rgb)})['embedding'].reshape(-1)
        elapsed = time.perf_counter() - started
        assert expected.shape == actual.shape == (512,)
        assert np.isfinite(actual).all()
        cosine = float(np.dot(expected, actual) / (np.linalg.norm(expected) * np.linalg.norm(actual)))
        error = float(np.max(np.abs(expected - actual)))
        assert cosine > 0.9999 and error < 0.001, (cosine, error)
        results.append({'cosine_to_pytorch': cosine, 'max_absolute_error': error, 'seconds': elapsed})
    report = {'weights_sha256': WEIGHTS, 'package_sha256': package_digest(args.output),
        'dimension': 512, 'precision': 'float32', 'compute_units': 'CPU_ONLY',
        'synthetic_only': True, 'cases': results,
        'versions': {'torch': torch.__version__, 'coremltools': ct.__version__}}
    args.output.with_suffix('.validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
