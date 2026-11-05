using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace ChenzhenPet;

// Shared-mode output is warmed once. Clicking swaps cached PCM instead of
// constructing a media decoder and opening a file on every interaction.
public sealed class FastAudio : IDisposable
{
    private readonly WasapiOut output;
    private readonly MMDevice device;
    private readonly Dictionary<int,float[]> clips=new();
    private readonly PcmMixer mixer=new();
    private volatile Exception? deviceError;
    public double Volume {set=>mixer.Volume=(float)value;}
    public FastAudio(Dictionary<int,byte[]> bytes)
    {
        using var enumerator=new MMDeviceEnumerator();device=enumerator.GetDefaultAudioEndpoint(DataFlow.Render,Role.Multimedia);
        var format=device.AudioClient.MixFormat;
        foreach(var item in bytes) clips[item.Key]=PcmClip.Decode(item.Value).Render(format.SampleRate,format.Channels);
        output=new WasapiOut(device,AudioClientShareMode.Shared,true,50);
        output.Init(new Provider(mixer,format));
        output.PlaybackStopped+=(_,e)=>{if(e.Exception!=null)deviceError=e.Exception;};
        output.Play();
    }
    public long Play(int id,double volume)
    {if(deviceError!=null)throw new InvalidOperationException("音频设备已变化，请重试",deviceError);Volume=volume;return mixer.Start(clips[id]);}
    public void CheckStatus(){if(deviceError!=null)throw deviceError;if(output.PlaybackState!=PlaybackState.Playing)throw new InvalidOperationException("音频输出已停止");}
    public bool Finished(long token)=>mixer.Finished(token);
    public void Stop()=>mixer.Stop();
    public void Dispose(){mixer.Stop();output.Stop();output.Dispose();device.Dispose();}
    private sealed class Provider(PcmMixer mixer,WaveFormat format):IWaveProvider
    {
        public WaveFormat WaveFormat=>format;
        private float[] scratch=[];
        public int Read(byte[] buffer,int offset,int count)
        {
            bool floating=format.Encoding==WaveFormatEncoding.IeeeFloat || (format is WaveFormatExtensible e && e.SubFormat==new Guid("00000003-0000-0010-8000-00aa00389b71"));
            if(floating && format.BitsPerSample==32){mixer.Read(MemoryMarshal.Cast<byte,float>(buffer.AsSpan(offset,count)));return count;}
            int bytesPerSample=format.BitsPerSample/8,n=count/bytesPerSample;
            if(scratch.Length<n)scratch=new float[n];mixer.Read(scratch.AsSpan(0,n));
            for(int i=0;i<n;i++)
            {
                double value=Math.Clamp(scratch[i],-1,1);int p=offset+i*bytesPerSample;
                if(format.BitsPerSample==16)System.Buffers.Binary.BinaryPrimitives.WriteInt16LittleEndian(buffer.AsSpan(p,2),(short)Math.Clamp((int)(value*32768),-32768,32767));
                else if(format.BitsPerSample==32)System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(buffer.AsSpan(p,4),(int)Math.Clamp((long)(value*2147483648d),int.MinValue,int.MaxValue));
                else if(format.BitsPerSample==24){int s=(int)Math.Clamp((long)(value*8388608),-8388608,8388607);buffer[p]=(byte)s;buffer[p+1]=(byte)(s>>8);buffer[p+2]=(byte)(s>>16);}
                else throw new NotSupportedException("Unsupported device PCM format");
            }
            return count;
        }
    }
}
