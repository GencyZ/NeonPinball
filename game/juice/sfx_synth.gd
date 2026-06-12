class_name SfxSynth extends RefCounted

# 大调五声音阶（跨两个八度），单位：半音。任意长度的连击序列都不会刺耳。
const PENTATONIC := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]

# 连击序号 n（从 1 起）→ pitch_scale。第 1 击 = 基准音 1.0；超表长封顶。
static func pitch_scale_for_combo(n: int) -> float:
	var idx := clampi(n - 1, 0, PENTATONIC.size() - 1)
	return pow(2.0, float(PENTATONIC[idx]) / 12.0)

# 程序化生成一个短促"叮"：正弦载波 + 快速指数衰减包络（霓虹合成器味）。
static func make_ping(sample_rate: int = 22050) -> AudioStreamWAV:
	var dur := 0.14
	var count := int(sample_rate * dur)
	var data := PackedByteArray()
	data.resize(count * 2)   # 16-bit = 2 bytes/sample
	var base_freq := 660.0
	for i in count:
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 22.0)
		var sample := sin(TAU * base_freq * t) * env
		var v := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
