use serde::{Deserialize, Serialize};

/// Inline style applied to a text segment.
///
/// Styles can be combined on the same [`InlineText`] by listing multiple values.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum InlineStyle {
    /// **Bold** text.
    Bold,
    /// __Underlined__ text.
    Underline,
    /// ~~Strikethrough~~ text.
    Strikethrough,
    /// Hyperlink. The inner `String` is the URL.
    Link(String),
    /// _Italic_ text.
    Italic,
    /// Colored text. The inner `String` is the color name (e.g. `"red"`).
    Color(String),
    /// Logical paragraph indentation level. Rendering chooses the point value.
    ParagraphIndent(u8),
}

/// A run of text sharing the same set of [`InlineStyle`]s.
///
/// A `Vec<InlineText>` is the canonical serializable representation of a
/// styled paragraph. [`RichText`](crate::RichText) is the in-memory editing
/// form; the two convert to each other without loss.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InlineText {
    /// Plain text content of this run.
    pub content: String,
    /// Styles applied to the whole run.
    pub styles: Vec<InlineStyle>,
}

#[cfg(test)]
mod tests {
    use super::{InlineStyle, InlineText};

    #[test]
    fn paragraph_indent_serde_round_trip() {
        for level in [0, 1, 6] {
            let style = InlineStyle::ParagraphIndent(level);
            let json = serde_json::to_string(&style).unwrap();
            assert_eq!(json, format!(r#"{{"ParagraphIndent":{level}}}"#));
            assert_eq!(serde_json::from_str::<InlineStyle>(&json).unwrap(), style);
        }
    }

    #[test]
    fn legacy_and_combined_styles_remain_compatible() {
        assert_eq!(
            serde_json::from_str::<InlineStyle>(r#""Bold""#).unwrap(),
            InlineStyle::Bold
        );
        let text = InlineText {
            content: "text".into(),
            styles: vec![
                InlineStyle::Bold,
                InlineStyle::Color("blue".into()),
                InlineStyle::ParagraphIndent(2),
            ],
        };
        let json = serde_json::to_string(&text).unwrap();
        assert_eq!(serde_json::from_str::<InlineText>(&json).unwrap(), text);
    }
}
