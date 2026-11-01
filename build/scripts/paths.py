from pathlib import Path
import os,shutil
PROJECT=Path(__file__).resolve().parents[2]
def tool(name):
    root=os.environ.get('VIVADO_ROOT' if name in ['vivado','xvlog','xelab','xsim'] else 'VITIS_ROOT')
    candidate=Path(root)/'bin'/name if root else None
    found=str(candidate) if candidate and candidate.is_file() else shutil.which(name)
    if not found:raise SystemExit('Tool not found: '+name+'; set VIVADO_ROOT/VITIS_ROOT or PATH')
    return Path(found).resolve()
