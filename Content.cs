using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Albion {
public sealed class ContentEntry {
    public string Path; public long Offset; public long Length;
}
public sealed class ContentInfo {
    public string XexSha256; public long Bytes; public int Files;
    public List<ContentEntry> Entries = new List<ContentEntry>();
}
public static class Content {
    static readonly byte[] Magic=Encoding.ASCII.GetBytes("MICROSOFT*XBOX*MEDIA");
    static void Exact(Stream s, byte[] b, int length) {
        int done=0; while(done<length) { int n=s.Read(b,done,length-done); if(n==0) throw new InvalidDataException("Truncated game image."); done+=n; }
    }
    static string Hash(Stream s, long length) {
        using(var hash=SHA256.Create()) {
            byte[] b=new byte[1024*1024];
            while(length>0) { int n=(int)Math.Min(b.Length,length); Exact(s,b,n); hash.TransformBlock(b,0,n,null,0); length-=n; }
            hash.TransformFinalBlock(new byte[0],0,0);
            return BitConverter.ToString(hash.Hash).Replace("-","");
        }
    }
    static string SafeName(string name) {
        if(String.IsNullOrWhiteSpace(name)||name=="."||name==".."||name.EndsWith(".")||name.EndsWith(" ")||name.IndexOfAny(Path.GetInvalidFileNameChars())>=0||name.IndexOfAny(new[]{'/', '\\', ':'})>=0)
            throw new InvalidDataException("Unsafe name in game image.");
        string stem=name.Split('.')[0].ToUpperInvariant();
        if(stem=="CON"||stem=="PRN"||stem=="AUX"||stem=="NUL"||System.Text.RegularExpressions.Regex.IsMatch(stem,@"^(COM|LPT)[1-9]$")) throw new InvalidDataException("Reserved filename in game image.");
        return name;
    }
    static long FindBase(FileStream s) {
        foreach(long volume in new long[]{0,0xFD90000,0x2080000,0x2000000}) {
            long at=volume+65536; if(at+32>s.Length) continue;
            s.Position=at; byte[] b=new byte[Magic.Length]; Exact(s,b,b.Length);
            bool equal=true;for(int i=0;i<b.Length;i++)if(b[i]!=Magic[i])equal=false;
            if(equal)return volume;
        }
        throw new InvalidDataException("Unsupported disc layout. Select a raw Xbox 360 ISO or extracted game files.");
    }
    static void Directory(FileStream s,long volume,uint sector,uint size,string prefix,int depth,ContentInfo info,HashSet<long> directories) {
        long at=volume+(long)sector*2048;
        if(depth>64||size>16*1024*1024||at<0||at+size>s.Length||!directories.Add(at))throw new InvalidDataException("Invalid disc directory.");
        if(size==0)return;
        byte[] table=new byte[size];s.Position=at;Exact(s,table,table.Length);
        var pending=new Stack<int>();var visited=new HashSet<int>();pending.Push(0);
        while(pending.Count>0) {
            int p=pending.Pop();if(p<0||p+14>table.Length||!visited.Add(p))throw new InvalidDataException("Invalid directory tree.");
            ushort left=BitConverter.ToUInt16(table,p),right=BitConverter.ToUInt16(table,p+2);
            if(left!=0)pending.Push(left*4);if(right!=0)pending.Push(right*4);
            int len=table[p+13];if(len==0||p+14+len>table.Length)throw new InvalidDataException("Invalid filename length.");
            string name=SafeName(Encoding.ASCII.GetString(table,p+14,len));
            string path=prefix.Length==0?name:prefix+"/"+name;
            uint fileSector=BitConverter.ToUInt32(table,p+4),fileSize=BitConverter.ToUInt32(table,p+8);
            if((table[p+12]&16)!=0) {
                if(path.Equals("data",StringComparison.OrdinalIgnoreCase)||path.StartsWith("data/",StringComparison.OrdinalIgnoreCase)) Directory(s,volume,fileSector,fileSize,path,depth+1,info,directories);
            } else if(path.Equals("default.xex",StringComparison.OrdinalIgnoreCase)||path.StartsWith("data/",StringComparison.OrdinalIgnoreCase)) {
                long offset=volume+(long)fileSector*2048;
                if(offset<0||offset+fileSize>s.Length)throw new InvalidDataException("Disc file is out of bounds.");
                info.Entries.Add(new ContentEntry{Path=path,Offset=offset,Length=fileSize});info.Bytes+=fileSize;
            }
        }
    }
    public static ContentInfo InspectIso(string path) {
        using(var s=File.OpenRead(path)) {
            long volume=FindBase(s);s.Position=volume+65536+20;byte[] root=new byte[8];Exact(s,root,8);
            var info=new ContentInfo();Directory(s,volume,BitConverter.ToUInt32(root,0),BitConverter.ToUInt32(root,4),"",0,info,new HashSet<long>());
            var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);ContentEntry xex=null;
            foreach(var e in info.Entries) {if(!paths.Add(e.Path))throw new InvalidDataException("Duplicate game path.");if(e.Path.Equals("default.xex",StringComparison.OrdinalIgnoreCase))xex=e;}
            if(xex==null||info.Entries.Count<2)throw new InvalidDataException("Game executable or data is missing.");
            s.Position=xex.Offset;info.XexSha256=Hash(s,xex.Length);info.Files=info.Entries.Count;return info;
        }
    }
    public static void ExtractIso(string path,string destination,string expectedHash,Action<long,long,string> progress,Func<bool> cancelled) {
        var info=InspectIso(path);if(!info.XexSha256.Equals(expectedHash,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Unsupported game executable; nothing extracted.");
        string root=Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
        if(System.IO.Directory.Exists(root))throw new IOException("Extraction destination already exists.");
        System.IO.Directory.CreateDirectory(root);
        byte[] buffer=new byte[4*1024*1024];long done=0;
        using(var source=File.OpenRead(path)) foreach(var entry in info.Entries) {
            string target=Path.GetFullPath(Path.Combine(root,entry.Path.Replace('/',Path.DirectorySeparatorChar)));
            if(!target.StartsWith(root,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Path escapes extraction directory.");
            System.IO.Directory.CreateDirectory(Path.GetDirectoryName(target));source.Position=entry.Offset;
            using(var output=new FileStream(target,FileMode.CreateNew,FileAccess.Write)) {
                long remaining=entry.Length;
                while(remaining>0) {
                    if(cancelled!=null&&cancelled())throw new OperationCanceledException("Setup cancelled. Source files were not changed.");
                    int n=(int)Math.Min(buffer.Length,remaining);Exact(source,buffer,n);output.Write(buffer,0,n);remaining-=n;done+=n;
                    if(progress!=null)progress(done,info.Bytes,entry.Path);
                }
            }
        }
    }
}
}
