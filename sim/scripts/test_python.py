"""Run PS/display and camera-control regressions from this package."""
from pathlib import Path
import json,sys,unittest
root=Path(__file__).resolve().parents[2]
(root/'sim/results/generated').mkdir(parents=True,exist_ok=True)
sys.dont_write_bytecode=True
sys.path.insert(0,str(root/'src/software/python'))
suite=unittest.TestSuite(unittest.defaultTestLoader.discover(str(root/'sim/tests'),pattern=name) for name in ['test_scene.py','test_r4_ps.py','test_camera_control.py','test_dependencies.py'])
result=unittest.TextTestRunner(verbosity=2).run(suite)
record=dict(passed=result.wasSuccessful(),tests=result.testsRun,failures=len(result.failures),errors=len(result.errors),scope='PS, scene and camera-control regressions; not physical camera timing')
(root/'sim/results/generated/python-reproduced.json').write_text(json.dumps(record,indent=2)+'\n')
raise SystemExit(0 if result.wasSuccessful() else 1)
