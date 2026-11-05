using System;
using System.Buffers.Binary;

namespace ChenzhenPet;

public sealed record PcmClip(int SampleRate, float[] Mono)
{
    public static PcmClip Decode(byte[] wav)
    {
        if (wav.Length < 44 || System.Text.Encoding.ASCII.GetString(wav,0,4)!="RIFF" || System.Text.Encoding.ASCII.GetString(wav,8,4)!="WAVE") throw new ArgumentException("Invalid WAV");
        int rate=0,channels=0,bits=0,format=0; ReadOnlySpan<byte> data=default;
        for(int p=12;p+8<=wav.Length;)
        {
            int size=BinaryPrimitives.ReadInt32LittleEndian(wav.AsSpan(p+4,4));
            if(size<0 || (long)p+8+size>wav.Length) throw new ArgumentException("Invalid WAV chunk");
            string id=System.Text.Encoding.ASCII.GetString(wav,p,4);var chunk=wav.AsSpan(p+8,size);
            if(id=="fmt ") { format=BinaryPrimitives.ReadInt16LittleEndian(chunk); channels=BinaryPrimitives.ReadInt16LittleEndian(chunk[2..]);rate=BinaryPrimitives.ReadInt32LittleEndian(chunk[4..]);bits=BinaryPrimitives.ReadInt16LittleEndian(chunk[14..]); }
            if(id=="data")data=chunk;
            p+=8+size+(size&1);
        }
        if(format!=1 || bits!=16 || channels!=1 || rate<=0 || data.Length==0 || data.Length%2!=0)throw new ArgumentException("Expected mono PCM16");
        var samples=new float[data.Length/2];for(int i=0;i<samples.Length;i++)samples[i]=BinaryPrimitives.ReadInt16LittleEndian(data[(i*2)..])/32768f;
        return new(rate,samples);
    }
    public float[] Render(int sampleRate,int channels)
    {
        int frames=(int)Math.Round((double)Mono.Length*sampleRate/SampleRate);var data=new float[frames*channels];
        for(int i=0;i<frames;i++)
        {
            double p=(double)i*SampleRate/sampleRate;int a=Math.Min((int)p,Mono.Length-1),b=Math.Min(a+1,Mono.Length-1);
            float value=Mono[a]+(Mono[b]-Mono[a])*(float)(p-a);
            for(int c=0;c<Math.Min(channels,2);c++)data[i*channels+c]=value;
        }
        return data;
    }
}
public sealed class PcmMixer
{
    private readonly object gate=new();
    private float[]? current;
    private int position;
    private long token,finished;
    private float volume=.5f;
    public float Volume { get=>System.Threading.Volatile.Read(ref volume); set=>System.Threading.Volatile.Write(ref volume,value); }
    public long Start(float[] samples) { lock(gate){ token++;current=samples;position=0;return token; } }
    public void Stop() { lock(gate){token++;current=null;position=0;} }
    public bool Finished(long value) {lock(gate)return finished==value;}
    public void Read(Span<float> destination)
    {
        lock(gate)
        {
            destination.Clear();if(current==null)return;
            int count=Math.Min(destination.Length,current.Length-position);float volume=Math.Clamp(Volume,0,1);
            for(int i=0;i<count;i++)destination[i]=current[position+i]*volume;
            position+=count;if(position>=current.Length){finished=token;current=null;}
        }
    }
}
