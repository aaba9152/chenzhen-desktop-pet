using System;
using System.IO;
using System.Threading;
using System.Windows;

namespace ChenzhenPet;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        using var mutex = new Mutex(true, @"Local\ChenzhenPet.SingleInstance", out bool first);
        if (!first) return 0;
        var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
        try
        {
            app.DispatcherUnhandledException += (_, e) => { Log(e.Exception); e.Handled = true; app.Shutdown(1); };
            var pet = new PetWindow();
            app.Run(pet);
            return 0;
        }
        catch (Exception e)
        {
            Log(e); MessageBox.Show("陈震桌宠无法启动：" + e.Message, "陈震桌宠"); return 1;
        }
    }
    public static string DataDirectory => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ChenzhenPet");
    public static void Log(Exception e)
    {
        try { Directory.CreateDirectory(DataDirectory); File.AppendAllText(Path.Combine(DataDirectory, "error.log"), DateTimeOffset.Now + " " + e + Environment.NewLine); }
        catch (Exception) { /* A read-only profile must not cause a second unhandled exception. */ }
    }
}
