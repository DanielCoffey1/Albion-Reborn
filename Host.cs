using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

// A windowed host for the built-in Windows PowerShell/WPF launcher.
// Game and launcher windows have separate lifetimes; there is no console window.
internal static class AlbionRebornHost
{
    [STAThread]
    private static int Main()
    {
        try
        {
            string root = Directory.GetParent(AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar)).FullName;
            string script = Path.Combine(root, "AlbionReborn.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("Keep the out folder beside AlbionReborn.ps1.", script);
            InitialSessionState state = InitialSessionState.CreateDefault();
            state.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace runspace = RunspaceFactory.CreateRunspace(state))
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (PowerShell engine = PowerShell.Create())
                {
                    engine.Runspace = runspace;
                    engine.AddCommand(script);
                    engine.Invoke();
                    if (engine.InvocationStateInfo.State == PSInvocationState.Failed)
                        throw engine.InvocationStateInfo.Reason;
                }
            }
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Albion Reborn", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
