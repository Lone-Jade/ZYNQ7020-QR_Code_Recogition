"""USB UART terminal for Linux/Windows hosts. Requires pyserial; Ctrl+] exits."""
import argparse
import os
import sys
import time

def main():
    p=argparse.ArgumentParser();p.add_argument('--port',required=True);a=p.parse_args()
    import serial
    connection=serial.Serial(a.port,115200,bytesize=serial.EIGHTBITS,parity=serial.PARITY_NONE,
                             stopbits=serial.STOPBITS_ONE,timeout=0,xonxoff=False,rtscts=False,dsrdtr=False)
    saved=None
    if os.name!='nt':
        import termios,tty
        saved=termios.tcgetattr(sys.stdin.fileno());tty.setraw(sys.stdin.fileno())
    print('\r\n115200 8N1; Ctrl+] exits. Press Enter for the login prompt.\r\n',end='',flush=True)
    try:
        while True:
            data=connection.read(4096)
            if data:sys.stdout.buffer.write(data);sys.stdout.buffer.flush()
            if os.name=='nt':
                import msvcrt
                key=msvcrt.getwch().encode('utf-8') if msvcrt.kbhit() else b''
            else:
                import select
                key=os.read(sys.stdin.fileno(),64) if select.select([sys.stdin],[],[],0)[0] else b''
            if b'\x1d' in key:break
            if key:connection.write(key)
            time.sleep(.005)
    finally:
        connection.close()
        if saved is not None:termios.tcsetattr(sys.stdin.fileno(),termios.TCSADRAIN,saved)
if __name__=='__main__':main()
