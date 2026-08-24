using System.Globalization;

namespace PotatokenHub.Core;

/// <summary>
/// Plain-code lookup table rather than .resx satellite assemblies, mirroring the
/// macOS build so both platforms carry the same four languages in one place.
/// </summary>
public static class L
{
    public enum Language
    {
        System,
        Korean,
        English,
        Japanese,
        Chinese,
    }

    public static Language Preference
    {
        get => Settings.LanguagePreference;
        set => Settings.LanguagePreference = value;
    }

    public static Language Resolved
    {
        get
        {
            var preference = Preference;
            if (preference != Language.System) return preference;

            var code = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
            return code switch
            {
                "ko" => Language.Korean,
                "ja" => Language.Japanese,
                "zh" => Language.Chinese,
                _ => Language.English,
            };
        }
    }

    public static CultureInfo FormattingCulture => Resolved switch
    {
        Language.Korean => new CultureInfo("ko-KR"),
        Language.Japanese => new CultureInfo("ja-JP"),
        Language.Chinese => new CultureInfo("zh-CN"),
        _ => new CultureInfo("en-US"),
    };

    public static string T(string ko, string en, string ja, string zh) => Resolved switch
    {
        Language.Korean => ko,
        Language.Japanese => ja,
        Language.Chinese => zh,
        _ => en,
    };
}
