import torch
import torch.nn as nn
from itertools import chain
from torchvision.models import mobilenet_v3_small, MobileNet_V3_Small_Weights
from torchvision.models.segmentation import (
    lraspp_mobilenet_v3_large,
    LRASPP_MobileNet_V3_Large_Weights,
)

class CornerNet(nn.Module):
    """Direct corner regression: 8 numbers, one (x, y) pair per corner.

    Superseded by DocSegNet but kept for A/B comparison. Note the Linear below
    is why this architecture only ever accepts one input size.
    """
    def __init__(self, out_size: int = 8):
        super().__init__()

        # ImageNet-pretrained trunk instead of training feature extraction from
        # scratch on synthetic data alone -- the point is to bring in generic
        # real-photo features (texture, lighting, edges) that our synthetic
        # renderer only approximates. common.py's preprocessing already
        # normalises with ImageNet mean/std, so no change needed there.
        self.features = mobilenet_v3_small(weights=MobileNet_V3_Small_Weights.IMAGENET1K_V1).features

        self.head = nn.Sequential(
            nn.Flatten(),
            nn.Linear(7*7*576, out_size)
        )

    def forward(self, x):
        x = self.features(x)
        x = self.head(x)
        return x


class DocSegNet(nn.Module):
    """Per-pixel document mask, one logit channel.

    Why a mask instead of four numbers: corner regression has to answer "which
    corner is corner 0", and that assignment is discontinuous under rotation --
    see synth.py's canonicalize_corners and the MAX_ROLL_DEG cap it forced. A
    mask carries no ordering, so in-plane rotation stops being a special case
    and the corner ordering becomes a postprocessing decision on the contour,
    where it is plain geometry rather than something a network has to fit.

    LR-ASPP is the segmentation head from the MobileNetV3 paper itself, so it
    is built for this compute budget. Weights are COCO-with-VOC-labels: the
    classes are irrelevant to us, but the pretrained encoder *and decoder* are
    a closer transfer than ImageNet classification, being the same task type.

    Fully convolutional, so unlike CornerNet it accepts any input size and
    returns a mask at exactly those dims.
    """

    def __init__(self) -> None:
        super().__init__()
        # torchvision refuses num_classes=1 alongside pretrained weights (the
        # count has to match the checkpoint's 21 VOC classes), so take the
        # weights first and then re-point the two 1x1 classifier convs at a
        # single logit. Everything upstream of them -- which is all of the
        # pretrained knowledge -- is kept.
        self.net = lraspp_mobilenet_v3_large(
            weights=LRASPP_MobileNet_V3_Large_Weights.COCO_WITH_VOC_LABELS_V1,
        )
        head = self.net.classifier
        head.low_classifier = nn.Conv2d(head.low_classifier.in_channels, 1, kernel_size=1)
        head.high_classifier = nn.Conv2d(head.high_classifier.in_channels, 1, kernel_size=1)

    def forward(self, x):
        # torchvision segmentation models return an OrderedDict. Unwrap it here
        # so export.py and eval.py deal in plain tensors like every other model.
        return self.net(x)["out"]

if __name__ == "__main__":
    net = DocSegNet()
    x = torch.zeros(3, 3, 300, 300)
    t = x
    print("----SHAPES----")
    print("Shape: ", t.shape)
    for l in net.children():
        print(l)
        t = l(t)

    print("---I/O, PARAMS---")
    print("input: ", x.shape)
    print("output: ", t["out"].shape)
    print("params: ", sum([p.numel() for p in net.parameters()]))
