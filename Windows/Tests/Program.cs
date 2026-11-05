using System;
using System.IO;
using System.Linq;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text.Json;
using ChenzhenPet;

static void Check(bool ok, string message)
{
    if (!ok) throw new Exception(message);
    Console.WriteLine("PASS " + message);
}
string root = Path.GetFullPath(args[0]);
int[] ids = [3, 1, 2, 5, 4, 6];
for (int seed = 0; seed < 20; seed++)
{
    var bag = new ClipSequence(seed); int last = 0;
    for (int round = 0; round < 100; round++)
    {
        int[] values = new int[6];
        for (int i = 0; i < 6; i++) { values[i] = bag.Next(ids); CheckNoPrint(values[i] != last); last = values[i]; }
        CheckNoPrint(values.Distinct().Count() == 6);
    }
}
Console.WriteLine("PASS 2000 ordered rounds: no within-round or boundary repeats");
var orderCheck = new ClipSequence(11);
Check(Enumerable.Range(0, 12).Select(_ => orderCheck.Next(ids)).SequenceEqual(ids.Concat(ids)), "two cycles preserve configured order");
var interruptedBag = new ClipSequence(5);
int firstPick = interruptedBag.Next(ids);
int secondPick = interruptedBag.Next(ids);
Check(firstPick != secondPick, "next click advances without immediate repetition");
var heardLater = new System.Collections.Generic.List<int> { secondPick };
for (int i = 0; i < 5; i++) heardLater.Add(interruptedBag.Next(ids));
Check(heardLater.Contains(firstPick), "interrupted clip recurs in the next ordered cycle");
static void CheckNoPrint(bool condition) { if (!condition) throw new Exception("Random sequence violation"); }
double testWidth = 260, testHeight = (testWidth - 16) * (956.0 / 1070.0) + 52 + 114;
var ratios = new[] { 956.0 / 1070.0, 1401.0 / 1123.0, 1.0 };
var avatarRects = ratios.Select(r => Placement.AvatarRect(testWidth, testHeight, r)).ToArray();
Check(avatarRects.All(r => Math.Abs(r.height - avatarRects[0].height) < .001 && Math.Abs(r.x + r.width / 2 - testWidth / 2) < .001) && avatarRects.Select((r, i) => Math.Abs(r.height / r.width - ratios[i]) < .001).All(x => x), "portrait heights and aspect ratios match");
Check(Placement.ResizeWidth(260, 80, 2) == 300 && Placement.ResizeWidth(260, 500, 1) == 340 && Placement.ResizeWidth(260, -500, 1) == 190, "drag resize respects DPI and size limits");
Check(!Placement.IsDrag(3, 0, 1) && Placement.IsDrag(5, 0, 1) && !Placement.IsDrag(5, 0, 2), "click/drag threshold and DPI");
Check(Placement.Clamp(-9000, 8000, 260, 270, 0, 0, 1920, 1040) == (0, 770), "disconnected monitor position recovers");
Check(Placement.Clamp(10, 10, 340, 360, -1920, 0, 300, 200) == (-1920, 0), "small/negative-coordinate monitor clamping");
var prefs = new Preferences { Volume = 10, Size = double.NaN, X = double.PositiveInfinity };
prefs.Sanitize(); Check(prefs.Volume == 1 && prefs.Size == 260 && prefs.X == null, "invalid settings sanitized");
string folder = Path.Combine(root, "tmp", "windows-core-tests"); Directory.CreateDirectory(folder);
string settings = Path.Combine(folder, "settings.json");
new Preferences { Volume = .65, Size = 340, X = -1200, Y = 500 }.Save(settings);
var restored = Preferences.Read(settings);
Check(restored.Volume == .65 && restored.Size == 340 && restored.X == -1200 && restored.Y == 500, "settings save/reload");
File.WriteAllText(settings, "corrupt"); Check(Preferences.Read(settings).Volume == .5, "corrupt settings fall back safely");
Directory.Delete(folder, true);
var clips = JsonSerializer.Deserialize<Clip[]>(File.ReadAllText(Path.Combine(root, "Assets/clips.json")))!;
Check(clips.Length == 6 && clips.Select(c => c.id).SequenceEqual(ids), "six shared clips in requested order");
var portraits = JsonSerializer.Deserialize<Portrait[]>(File.ReadAllText(Path.Combine(root, "Assets/portraits.json")))!;
Check(portraits.Length == 3 && portraits.Select(p => p.id).Distinct().Count() == 3 && portraits.All(p => p.mouth.Length == 2 && p.head.Length == 2 && p.mouth.Concat(p.head).All(x => x >= 0 && x <= 1)), "three portraits with normalized animation anchors");
foreach(var c in clips)
{
    var pcm=PcmClip.Decode(File.ReadAllBytes(Path.Combine(root,"Assets/Clips",c.file)));
    CheckNoPrint(Math.Abs((double)pcm.Mono.Length/pcm.SampleRate-c.duration)<1d/pcm.SampleRate);
    var stereo=pcm.Render(48000,2);CheckNoPrint(stereo.Length==2*(int)Math.Round(c.duration*48000));
}
Console.WriteLine("PASS six decoded PCM durations and preloaded stereo resampling");
var mixer=new PcmMixer { Volume=1 };
long first=mixer.Start(new float[] {.1f,.2f,.3f,.4f});var output=new float[2];mixer.Read(output);
CheckNoPrint(output.SequenceEqual(new float[] {.1f,.2f}));
long second=mixer.Start(new float[] {-.5f,-.6f});mixer.Read(output);
Check(output.SequenceEqual(new float[] {-.5f,-.6f}) && mixer.Finished(second) && !mixer.Finished(first),"PCM interruption switches immediately without queue/overlap");
mixer.Stop();mixer.Read(output);Check(output.All(x=>x==0),"idle audio output stays silent");
Check(FeedingReply.Select("noodles", null, 2) == 1 && FeedingReply.Select("pour", 6, 2) == 3, "noodles and pour fixed responses");
Check(FeedingReply.Select("soda", 6, 3) == 2 && FeedingReply.Select("coffee", 6, 2) == 4 && FeedingReply.Select("noodles", 6, 2) == 4, "soda conversation responses and priority");
Check(FeedingReply.Select("coffee", null, 2) == 2 && FeedingReply.Select("soda", null, 3) == 3, "other drinks use random fallback");
var library = JsonSerializer.Deserialize<ActionLibrary>(File.ReadAllText(Path.Combine(root,"Assets/actions.json")))!;
library.Validate();
Check(library.actions.First(a => a.id == "noodles").icon == "beef" && library.actions.First(a => a.id == "noodles").layers.Select(l => l.sprite).SequenceEqual(new[] { "beef", "chopsticks-beef" }), "beef action has chopsticks");
Check(portraits.Select(p => p.name).SequenceEqual(new[] { "黄色长发", "黑色长发", "短发" }), "requested portrait menu labels");
var beefAction = library.actions.First(a => a.id == "noodles");
var coffeeAction = library.actions.First(a => a.id == "coffee");
var testAvatar = new SceneRect(8,114,244,218);
var beefStart = new ScenePoint(54,360);
var beefPoses = ActionSampler.Sample(beefAction,.92,library,testAvatar,beefStart,1,1);
var coffeePoses = ActionSampler.Sample(coffeeAction,.67,library,testAvatar,beefStart,1,1);
Check(beefPoses.Any(p => p.sprite == "chopsticks-beef" && p.alpha > .9) && coffeePoses.Any(p => p.sprite == "coffee-drops" && p.alpha > .8), "new beef and coffee effects visible during interaction");
Check(library.actions.Select(a => a.duration).SequenceEqual(new[] { 1.44,1.24,1.36,1.68 }), "four action durations and shared manifest");
Check(new SceneRect(8,114,244,218).Contains(new ScenePoint(100,150)) && !new SceneRect(8,114,244,218).Contains(new ScenePoint(100,350)), "toolbar excluded from feeding target");
var generation = new InteractionGeneration(); long old = generation.Next(); long latest = generation.Next();
Check(!generation.IsCurrent(old) && generation.IsCurrent(latest), "stale callbacks cannot own new interaction");
var fixture = Path.Combine(root,"verification/action-samples-1.3.3.json");
Check(File.Exists(fixture), "shared macOS scene fixture present");
if (File.Exists(fixture))
{
    using var doc = JsonDocument.Parse(File.ReadAllText(fixture)); int frames = 0;
    foreach (var row in doc.RootElement.EnumerateArray())
    {
        double width = row.GetProperty("width").GetDouble(), height = row.GetProperty("height").GetDouble(), time = row.GetProperty("time").GetDouble(), unit = width/260;
        int index = Array.FindIndex(library.actions,a => a.id == row.GetProperty("action").GetString());
        var action = library.actions[index]; var avatar = new SceneRect(8,44+70*unit,width-16,height-52-114*unit);
        var start = new ScenePoint((width-194*unit)/2+index*50*unit+22*unit,height-24*unit);
        double scale = ActionSampler.Squash(time,action.duration);
        CheckNoPrint(Math.Abs(scale-row.GetProperty("squash").GetDouble()) < 1e-9);
        var poses = ActionSampler.Sample(action,time,library,avatar,start,unit,scale);
        var expected = row.GetProperty("poses"); CheckNoPrint(poses.Length == expected.GetArrayLength());
        for(int i=0;i<poses.Length;i++)
        {
            var p=poses[i];var e=expected[i];
            CheckNoPrint(p.sprite==e.GetProperty("sprite").GetString());
            foreach(var value in new[] { ("x",p.center.x),("y",p.center.y),("width",p.width),("height",p.height),("rotation",p.rotation),("alpha",p.alpha) })
                CheckNoPrint(Math.Abs(value.Item2-e.GetProperty(value.Item1).GetDouble())<1e-7);
        }
        frames++;
    }
    Check(frames==84,"84 cross-platform scene samples at three sizes match macOS renderer");
}
// Inspect the compiled PE resources without loading Windows UI assemblies on macOS.
if (args.Length > 1)
{
    using var assembly = File.OpenRead(args[1]); using var pe = new PEReader(assembly);
    var metadata = pe.GetMetadataReader(); var resources = pe.GetSectionData(pe.PEHeaders.CorHeader!.ResourcesDirectory.RelativeVirtualAddress).GetContent();
    int checkedResources = 0;
    foreach (var handle in metadata.ManifestResources)
    {
        var resource = metadata.GetManifestResource(handle); string name = metadata.GetString(resource.Name);
        string? path = name switch
        {
            "Pet.face.png" => "Assets/face.png", "Pet.caption-bubble.png" => "Assets/caption-bubble.png", "Pet.clips.json" => "Assets/clips.json",
            "Pet.sources.json" => "materials/sources.json", "Pet.icon.ico" => "Windows/AppIcon.ico",
            "Pet.actions.json" => "Assets/actions.json", "Pet.portraits.json" => "Assets/portraits.json",
            _ when name.StartsWith("Pet.Portraits.") => "Assets/Portraits/"+name[14..],
            _ when name.StartsWith("Pet.Actions.") => "Assets/Actions/"+name[12..],
            _ => name.StartsWith("Pet.") && name.EndsWith(".wav") ? "Assets/Clips/" + name[4..] : null
        };
        if (path == null) continue;
        int offset = checked((int)resource.Offset);
        int length = BitConverter.ToInt32(resources.AsSpan().Slice(offset, 4));
        var actual = resources.AsSpan().Slice(offset + 4, length);
        Check(SHA256.HashData(actual).SequenceEqual(SHA256.HashData(File.ReadAllBytes(Path.Combine(root, path)))), "embedded asset hash " + name);
        checkedResources++;
    }
    Check(checkedResources == 24, "all twenty-four expected embedded assets present");
}
Console.WriteLine("PASS all Windows core/asset checks");
