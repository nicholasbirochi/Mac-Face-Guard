#!/usr/bin/env python3
"""Convert reviewed local MiniFASNet inputs. No network, camera or owner templates."""
import argparse
from collections import OrderedDict
import hashlib
import importlib.util
import json
from pathlib import Path
import time

REVISION = 'b6d5f04ad78778917853b25c778acef6d5626d15'
WEIGHTS = {
    '2.7_80x80_MiniFASNetV2.pth': 'a5eb02e1843f19b5386b953cc4c9f011c3f985d0ee2bb9819eea9a142099bec0',
    '4_0_0_80x80_MiniFASNetV1SE.pth': '84ee1d37d96894d5e82de5a57df044ef80a58be2b218b5ed7cdfd875ec2f5990',
}
SOURCE = {'MiniFASNet.py': 'e498c4ec5e1ddfaba62b941a126c19d65aa564999f3309661fe43ee8bf38acd7'}


def package_digest(path):
    digest = hashlib.sha256()
    for item in sorted(p for p in path.rglob('*') if p.is_file()):
        assert not item.is_symlink()
        digest.update(item.relative_to(path).as_posix().encode() + b'\0')
        digest.update(hashlib.sha256(item.read_bytes()).digest())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', type=Path, required=True, help='Silent-Face-Anti-Spoofing checkout')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output already exists; preserve it or choose a new path.')
    weights = args.upstream / 'resources' / 'anti_spoof_models'
    for name, expected in WEIGHTS.items():
        assert hashlib.sha256((weights / name).read_bytes()).hexdigest() == expected, name
    for name, expected in SOURCE.items():
        assert hashlib.sha256((args.upstream / 'src' / 'model_lib' / name).read_bytes()).hexdigest() == expected, name
    import coremltools as ct
    import numpy as np
    from PIL import Image
    import torch
    import torch.nn.functional as F
    # Load only the hash-checked file; the checkout never joins sys.path.
    spec = importlib.util.spec_from_file_location('MiniFASNet', args.upstream / 'src' / 'model_lib' / 'MiniFASNet.py')
    upstream = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(upstream)
    MiniFASNetV1SE, MiniFASNetV2 = upstream.MiniFASNetV1SE, upstream.MiniFASNetV2

    torch.set_num_threads(2)

    def load(factory, name):
        # Upstream: kernel ((80 + 15) // 16, (80 + 15) // 16); checkpoints saved from DataParallel.
        model = factory(conv6_kernel=(5, 5))
        state = torch.load(weights / name, map_location='cpu', weights_only=True)
        state = OrderedDict((k[7:] if k.startswith('module.') else k, v) for k, v in state.items())
        model.load_state_dict(state, strict=True)
        return model.eval()

    class Ensemble(torch.nn.Module):
        """Same as upstream test.py: mean of both softmax outputs; class 1 is a real face."""
        def __init__(self):
            super().__init__()
            self.wide = load(MiniFASNetV2, '2.7_80x80_MiniFASNetV2.pth')
            self.wider = load(MiniFASNetV1SE, '4_0_0_80x80_MiniFASNetV1SE.pth')

        def forward(self, wide, wider):
            return (F.softmax(self.wide(wide), dim=1) + F.softmax(self.wider(wider), dim=1)) / 2

    model = Ensemble().eval()
    zeros = torch.zeros(1, 3, 80, 80)
    with torch.no_grad():
        traced = torch.jit.trace(model, (zeros, zeros))
    # Upstream feeds OpenCV BGR pixels as raw 0...255 floats (its ToTensor does not divide by 255).
    image = dict(shape=(1, 3, 80, 80), scale=1.0, bias=[0, 0, 0], color_layout=ct.colorlayout.BGR)
    converted = ct.convert(traced,
        inputs=[ct.ImageType(name='wide', **image), ct.ImageType(name='wider', **image)],
        outputs=[ct.TensorType(name='probabilities')],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT32,
        compute_units=ct.ComputeUnit.CPU_ONLY)
    converted.short_description = ('MiniFASNetV2 (crop 2.7) + MiniFASNetV1SE (crop 4.0), 80x80 BGR; '
        'mean softmax [fake 2D, real, fake 3D]. Experimental PAD; not validated on this Mac.')
    converted.license = 'Upstream Apache-2.0 (minivision-ai/Silent-Face-Anti-Spoofing). Weights not redistributed by MacFaceGuard.'
    converted.user_defined_metadata['source_revision'] = REVISION
    for name, digest in WEIGHTS.items():
        converted.user_defined_metadata['weights_sha256_' + name.split('_')[0]] = digest
    converted.save(str(args.output))

    # Synthetic inputs exercise conversion and preprocessing, not anti-spoofing accuracy.
    rng = np.random.default_rng(7)
    cases = [np.zeros((80, 80, 3), dtype=np.uint8), np.full((80, 80, 3), 255, dtype=np.uint8)]
    cases += [rng.integers(0, 256, (80, 80, 3), dtype=np.uint8) for _ in range(6)]
    results = []
    for index, rgb in enumerate(cases):
        other = cases[(index + 3) % len(cases)]
        def tensor(pixels):
            return torch.from_numpy(pixels[:, :, ::-1].transpose(2, 0, 1).copy()).float().unsqueeze(0)
        with torch.no_grad():
            expected = model(tensor(rgb), tensor(other)).numpy().reshape(-1)
        started = time.perf_counter()
        actual = converted.predict({'wide': Image.fromarray(rgb), 'wider': Image.fromarray(other)})['probabilities'].reshape(-1)
        elapsed = time.perf_counter() - started
        assert expected.shape == actual.shape == (3,)
        assert np.isfinite(actual).all() and abs(float(actual.sum()) - 1) < 1e-4
        error = float(np.max(np.abs(expected - actual)))
        assert error < 1e-3, error
        results.append({'max_absolute_error': error, 'seconds': elapsed})
    report = {'source_revision': REVISION, 'weights_sha256': WEIGHTS, 'package_sha256': package_digest(args.output),
        'classes': ['fake_2d', 'real', 'fake_3d'], 'precision': 'float32', 'compute_units': 'CPU_ONLY',
        'synthetic_only': True, 'cases': results,
        'versions': {'torch': torch.__version__, 'coremltools': ct.__version__}}
    args.output.with_suffix('.validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
