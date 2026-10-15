using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Windows.Forms;

internal static class AlbionInstaller {
    const string BuildId="__BUILD_ID__";
    const string PayloadHash="__PAYLOAD_HASH__";
    [STAThread] static int Main(string[] args) {
        try {
            if(args.Length>0 && args[0]=="--verify") { Verify(); return 0; }
            if(args.Length==2 && args[0]=="--extract-to") { Install(args[1],null,false); return 0; }
            Application.EnableVisualStyles(); Application.Run(CreateWindow()); return 0;
        } catch(Exception e) { if(args.Length==0)MessageBox.Show(e.Message,"Albion Reborn setup",MessageBoxButtons.OK,MessageBoxIcon.Error); return 1; }
    }
    static void Verify() {
        using(var s=Assembly.GetExecutingAssembly().GetManifestResourceStream("AlbionPayload.zip"))
        using(var hash=SHA256.Create()) {
            if(s==null || BitConverter.ToString(hash.ComputeHash(s)).Replace("-","")!=PayloadHash)throw new InvalidDataException("Installer payload integrity check failed.");
        }
    }
    static string Install(string root,Action<int,string> progress,bool shortcut) {
        Verify();
        string parent=Path.GetFullPath(root);
        Directory.CreateDirectory(parent);
        string target=Path.Combine(parent,BuildId);
        if(Directory.Exists(target))throw new IOException("This installer build is already installed at "+target);
        string stage=Path.Combine(parent,".install-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(stage);
        string prefix=Path.GetFullPath(stage).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
        using(var payload=Assembly.GetExecutingAssembly().GetManifestResourceStream("AlbionPayload.zip"))
        using(var zip=new ZipArchive(payload,ZipArchiveMode.Read)) {
            long total=0,done=0;foreach(var entry in zip.Entries)total+=entry.Length;
            if(total>2147483648L||zip.Entries.Count>10000)throw new InvalidDataException("Installer payload is too large.");
            foreach(var entry in zip.Entries) {
                string path=Path.GetFullPath(Path.Combine(stage,entry.FullName));
                if(!path.StartsWith(prefix,StringComparison.OrdinalIgnoreCase)||entry.FullName.Contains(":"))throw new InvalidDataException("Unsafe installer path.");
                if(String.IsNullOrEmpty(entry.Name)){Directory.CreateDirectory(path);continue;}
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                using(var input=entry.Open())using(var output=new FileStream(path,FileMode.CreateNew))input.CopyTo(output);
                done+=entry.Length;if(progress!=null)progress(total==0?100:(int)(done*100/total),entry.FullName);
            }
        }
        Directory.Move(stage,target);
        string exe=Path.Combine(target,"out","AlbionReborn.exe");
        if(shortcut) {
            Type shellType=Type.GetTypeFromProgID("WScript.Shell");dynamic shell=Activator.CreateInstance(shellType);
            dynamic link=shell.CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"Albion Reborn.lnk"));
            link.TargetPath=exe;link.WorkingDirectory=target;link.IconLocation=Path.Combine(target,"assets","AlbionReborn.ico")+",0";link.Description="Choose your next story in Albion.";link.Save();
        }
        return exe;
    }
    static Form CreateWindow() {
        var f=new Form{Text="Install Albion Reborn",ClientSize=new Size(650,390),StartPosition=FormStartPosition.CenterScreen,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,BackColor=Color.FromArgb(16,27,34),ForeColor=Color.FromArgb(242,230,205),Font=new Font("Segoe UI",10)};
        f.Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        var title=new Label{Text="Albion Reborn",Font=new Font("Georgia",30),AutoSize=true,Location=new Point(28,24)};
        var description=new Label{Text="Your Fable collection, ready to play.\nInstall the launcher, then choose your own game ISO or extracted files.\nBundled runtimes work offline. No Git account or build tools required.",Location=new Point(30,88),Size=new Size(590,75)};
        var path=new TextBox{Text=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"AlbionReborn","App"),Location=new Point(30,184),Size=new Size(488,28)};
        var browse=new Button{Text="Browse...",Location=new Point(530,182),Size=new Size(90,29)};
        var bar=new ProgressBar{Location=new Point(30,235),Size=new Size(590,10)};
        var detail=new Label{Text="Per-user installation. Existing game files and saves stay intact.",Location=new Point(30,259),Size=new Size(590,42)};
        var launch=new CheckBox{Text="Open Albion Reborn when finished",Checked=true,AutoSize=true,Location=new Point(30,332)};
        var install=new Button{Text="Install",Location=new Point(498,320),Size=new Size(122,40),BackColor=Color.FromArgb(212,183,121),ForeColor=Color.FromArgb(21,32,40),FlatStyle=FlatStyle.Flat};
        bool busy=false;var worker=new BackgroundWorker{WorkerReportsProgress=true};string installedExe=null;
        browse.Click+=(sender,e)=>{using(var picker=new FolderBrowserDialog{Description="Choose the launcher installation parent folder",SelectedPath=path.Text})if(picker.ShowDialog(f)==DialogResult.OK)path.Text=picker.SelectedPath;};
        worker.DoWork+=(sender,e)=>{installedExe=Install((string)e.Argument,(percent,name)=>worker.ReportProgress(percent,name),true);};
        worker.ProgressChanged+=(sender,e)=>{bar.Value=e.ProgressPercentage;detail.Text=(string)e.UserState;};
        worker.RunWorkerCompleted+=(sender,e)=>{busy=false;if(e.Error!=null){detail.Text=e.Error.Message;install.Enabled=true;path.Enabled=true;browse.Enabled=true;return;}bar.Value=100;detail.Text="Installed. Use Set up / update on a game card to add your game files.";install.Text="Done";install.Enabled=true;install.Tag="done";if(launch.Checked){Process.Start(new ProcessStartInfo(installedExe){WorkingDirectory=Path.GetDirectoryName(Path.GetDirectoryName(installedExe)),UseShellExecute=true});f.Close();}};
        install.Click+=(sender,e)=>{if((string)install.Tag=="done"){f.Close();return;}busy=true;install.Enabled=false;path.Enabled=false;browse.Enabled=false;detail.Text="Verifying and installing...";worker.RunWorkerAsync(path.Text);};
        f.FormClosing+=(sender,e)=>{if(busy){e.Cancel=true;detail.Text="Please wait for installation to finish.";}};
        f.Controls.AddRange(new Control[]{title,description,path,browse,bar,detail,launch,install});return f;
    }
}
