using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace FileQrSender;

/// <summary>FDQR v1 sender. Frames are binary envelopes encoded as the text prefix "FDQR1:" plus Base64URL.</summary>
public sealed class TransmissionSession
{
    private const int ParityGroupSize = 8;
    private const int MetadataInterval = 20;
    private const int InitialMetadataFrames = 6;
    private readonly byte[] _metadata;
    private readonly ulong _sessionId;

    public string FilePath { get; }
    public long FileLength { get; }
    public int PayloadSize { get; }
    public int DataFrameCount { get; }
    public string FileHash { get; }

    public TransmissionSession(string filePath, int payloadSize)
    {
        FilePath = filePath;
        FileLength = new FileInfo(filePath).Length;
        PayloadSize = payloadSize;
        DataFrameCount = checked((int)Math.Max(1, (FileLength + payloadSize - 1) / payloadSize));
        _sessionId = BitConverter.ToUInt64(RandomNumberGenerator.GetBytes(sizeof(ulong)));
        using (var stream = File.OpenRead(filePath))
            FileHash = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        _metadata = JsonSerializer.SerializeToUtf8Bytes(new Metadata("FDQR", 1, Path.GetFileName(filePath), FileLength, PayloadSize, DataFrameCount, ParityGroupSize, FileHash));
    }

    public TimelineFrame GetTimelineFrame(int timelineIndex)
    {
        // Camera startup and focus can take several frames. Repeat metadata briefly at the beginning,
        // then once per 20 transport frames so a receiver may join mid-stream.
        if (timelineIndex < InitialMetadataFrames)
            return CreateFrame(FrameType.Metadata, 0, DataFrameCount, _metadata, 0, "元数据帧（文件信息）");

        var afterInitialMetadata = timelineIndex - InitialMetadataFrames;
        if (afterInitialMetadata % (MetadataInterval + 1) == MetadataInterval)
            return CreateFrame(FrameType.Metadata, 0, DataFrameCount, _metadata, 0, "元数据帧（文件信息）");

        // Every pass alternates direction. The receiver stores by frame number, so it can keep
        // accepting later frames while an earlier one was missed. Crucially, a late missed frame
        // becomes an early frame in the following reverse pass instead of waiting a whole pass.
        var transportOrdinal = afterInitialMetadata - (afterInitialMetadata + 1) / (MetadataInterval + 1);
        var pass = transportOrdinal / TransportFrameCount;
        var positionInPass = transportOrdinal % TransportFrameCount;
        var isReversePass = pass % 2 == 1;
        var transportIndex = isReversePass ? TransportFrameCount - 1 - positionInPass : positionInPass;
        var groupSpan = ParityGroupSize + 1;
        var group = transportIndex / groupSpan;
        var position = transportIndex % groupSpan;
        var groupStart = group * ParityGroupSize;
        var countInGroup = Math.Min(ParityGroupSize, DataFrameCount - groupStart);

        if (position < countInGroup)
        {
            var dataIndex = groupStart + position;
            var direction = isReversePass ? "逆序补帧" : "正序发送";
            return CreateFrame(FrameType.Data, dataIndex, DataFrameCount, ReadChunk(dataIndex), dataIndex,
                $"{direction} · 数据帧 {dataIndex + 1:N0} / {DataFrameCount:N0}");
        }

        // The extra position is an XOR parity frame. Its sequence number is the first data index in the group.
        return CreateFrame(FrameType.Parity, groupStart, DataFrameCount, CreateParity(groupStart, countInGroup), groupStart,
            $"{(isReversePass ? "逆序补帧" : "正序发送")} · 冗余帧（保护数据帧 {groupStart + 1:N0}–{groupStart + countInGroup:N0}）");
    }

    private int TransportFrameCount => DataFrameCount + (DataFrameCount + ParityGroupSize - 1) / ParityGroupSize;

    private TimelineFrame CreateFrame(FrameType type, int number, int total, byte[] payload, int dataIndex, string description)
    {
        var packet = PacketCodec.Encode(_sessionId, type, number, total, payload);
        return new TimelineFrame(packet, dataIndex, description);
    }

    private byte[] ReadChunk(int index)
    {
        var length = (int)Math.Min(PayloadSize, Math.Max(0, FileLength - (long)index * PayloadSize));
        var data = new byte[length];
        if (length == 0) return data;
        using var stream = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.RandomAccess);
        stream.Position = (long)index * PayloadSize;
        stream.ReadExactly(data);
        return data;
    }

    private byte[] CreateParity(int groupStart, int count)
    {
        // Padded XOR lets the receiver restore one lost frame in the group. The final frame length is inferred from metadata.
        var parity = new byte[PayloadSize];
        for (var i = 0; i < count; i++)
        {
            var part = ReadChunk(groupStart + i);
            for (var j = 0; j < part.Length; j++) parity[j] ^= part[j];
        }
        return parity;
    }

    private sealed record Metadata(string Magic, int Version, string FileName, long FileSize, int ChunkSize, int ChunkCount, int ParityGroupSize, string Sha256);
}

public sealed record TimelineFrame(string Encoded, int DataIndex, string Description);

public enum FrameType : byte { Metadata = 1, Data = 2, Parity = 3 }

public static class PacketCodec
{
    // Header, little-endian, 30 bytes: magic[4] | version[1] | type[1] | flags[2] | session[8] | number[4] | total[4] | length[2] | crc32[4].
    public static string Encode(ulong sessionId, FrameType type, int number, int total, byte[] payload)
    {
        if (payload.Length > ushort.MaxValue) throw new ArgumentOutOfRangeException(nameof(payload));
        var bytes = new byte[30 + payload.Length];
        Encoding.ASCII.GetBytes("FDQR").CopyTo(bytes, 0);
        bytes[4] = 1;
        bytes[5] = (byte)type;
        BitConverter.GetBytes(sessionId).CopyTo(bytes, 8);
        BitConverter.GetBytes(number).CopyTo(bytes, 16);
        BitConverter.GetBytes(total).CopyTo(bytes, 20);
        BitConverter.GetBytes((ushort)payload.Length).CopyTo(bytes, 24);
        BitConverter.GetBytes(Crc32.Compute(payload)).CopyTo(bytes, 26);
        payload.CopyTo(bytes, 30);
        return "FDQR1:" + Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }
}

public static class Crc32
{
    private static readonly uint[] Table = CreateTable();
    public static uint Compute(ReadOnlySpan<byte> data)
    {
        var value = 0xffffffffu;
        foreach (var b in data) value = Table[(int)((value ^ b) & 0xff)] ^ (value >> 8);
        return ~value;
    }
    private static uint[] CreateTable()
    {
        var table = new uint[256];
        for (var i = 0; i < table.Length; i++)
        {
            uint value = (uint)i;
            for (var bit = 0; bit < 8; bit++) value = (value & 1) == 1 ? 0xedb88320u ^ (value >> 1) : value >> 1;
            table[i] = value;
        }
        return table;
    }
}
