import sys
import os
from Crypto.Hash import keccak

if __name__ == "__main__":
    dirname = sys.argv[1]
    provenance_hash = keccak.new(digest_bits=256)
    filelist = []
    for filename in os.listdir(dirname):
        f = os.path.join(dirname,filename)
        if os.path.isfile(f):
            n = str((f.split('/')[-1]).split('.')[0])
            filelist.append((n,f))
    filelist.sort(key=lambda y: y[0])
    filelist = [f for n,f in filelist]
    for f in filelist:
        xml = open(f,"r").read()
        keccak_hash = keccak.new(digest_bits=256)
        keccak_hash.update(bytes(xml,'utf-8'))
        xml_hash = keccak_hash.hexdigest()
        provenance_hash.update(bytes.fromhex(xml_hash))
    print("Provenance hash:",provenance_hash.hexdigest())
