import math
import torch
import torch.nn as nn
from utils import util


def fuse_conv(conv, norm):
    fused_conv = torch.nn.Conv2d(conv.in_channels,
                                 conv.out_channels,
                                 kernel_size=conv.kernel_size,
                                 stride=conv.stride,
                                 padding=conv.padding,
                                 groups=conv.groups,
                                 bias=True).requires_grad_(False).to(
        conv.weight.device)

    w_conv = conv.weight.clone().view(conv.out_channels, -1)
    w_norm = torch.diag(
        norm.weight.div(torch.sqrt(norm.eps + norm.running_var)))
    fused_conv.weight.copy_(
        torch.mm(w_norm, w_conv).view(fused_conv.weight.size()))

    b_conv = torch.zeros(conv.weight.size(0),
                         device=conv.weight.device) if conv.bias is None else conv.bias
    b_norm = norm.bias - norm.weight.mul(norm.running_mean).div(
        torch.sqrt(norm.running_var + norm.eps))
    fused_conv.bias.copy_(
        torch.mm(w_norm, b_conv.reshape(-1, 1)).reshape(-1) + b_norm)

    return fused_conv


class Concat(nn.Module):
    """Concatenate a list of tensors along dimension."""

    def __init__(self, dimension=1):
        """Concatenates a list of tensors along a specified dimension."""
        super().__init__()
        self.d = dimension

    def forward(self, x):
        """Forward pass for the YOLOv8 mask Proto module."""
        return torch.cat(x, self.d)


class Conv(nn.Module):
    def __init__(self, inp, oup, k=1, s=1, p=None, g=1, d=1, act=True):
        super().__init__()
        self.conv = nn.Conv2d(inp, oup, k, s, self._pad(k, p), d, g, False)
        self.norm = nn.BatchNorm2d(oup)
        self.act = nn.SiLU(inplace=True) if act is True else nn.Identity()

    def forward(self, x):
        return self.act(self.norm(self.conv(x)))

    def forward_fuse(self, x):
        return self.act(self.conv(x))

    @staticmethod
    def _pad(k, p=None):
        if p is None:
            p = k // 2 if isinstance(k, int) else [x // 2 for x in k]
        return p


class Residual(nn.Module):
    def __init__(self, inp, g=1, k=(3, 3), e=0.5):
        super().__init__()
        self.conv1 = Conv(inp, int(inp * e), k[0], 1)
        self.conv2 = Conv(int(inp * e), inp, k[1], 1, g=g)

    def forward(self, x):
        return x + self.conv2(self.conv1(x))


class CSPBlock(torch.nn.Module):
    def __init__(self, in_ch, out_ch):
        super().__init__()
        self.conv1 = Conv(in_ch, out_ch // 2)
        self.conv2 = Conv(in_ch, out_ch // 2)
        self.conv3 = Conv(2 * (out_ch // 2), out_ch)
        self.res_m = torch.nn.Sequential(Residual(out_ch // 2, e=1.0),
                                         Residual(out_ch // 2, e=1.0))

    def forward(self, x):
        y = self.res_m(self.conv1(x))
        return self.conv3(torch.cat((y, self.conv2(x)), dim=1))


class CSP(torch.nn.Module):
    def __init__(self, in_ch, out_ch, n, csp, r=2):
        super().__init__()
        self.conv1 = Conv(in_ch, 2 * (out_ch // r))
        self.conv2 = Conv((2 + n) * (out_ch // r), out_ch)

        if not csp:
            self.res_m = torch.nn.ModuleList(
                Residual(out_ch // r) for _ in range(n))
        else:
            self.res_m = torch.nn.ModuleList(
                CSPBlock(out_ch // r, out_ch // r) for _ in range(n))

    def forward(self, x):
        y = list(self.conv1(x).chunk(2, 1))
        y.extend(m(y[-1]) for m in self.res_m)
        return self.conv2(torch.cat(y, dim=1))


class SPP(nn.Module):
    def __init__(self, inp, k=5):
        super().__init__()
        self.conv1 = Conv(inp, inp // 2, 1, 1)
        self.conv2 = Conv(inp // 2 * 4, inp, 1, 1)
        self.m = nn.MaxPool2d(k, stride=1, padding=k // 2)

    def forward(self, x):
        y = [self.conv1(x)]
        y.extend(self.m(y[-1]) for _ in range(3))
        return self.conv2(torch.cat(y, 1))


class Attention(nn.Module):
    def __init__(self, dim, num_head=8):
        super().__init__()
        self.num_head = num_head
        self.head_dim = dim // num_head
        self.key_dim = self.head_dim // 2
        self.scale = self.key_dim ** -0.5
        h = dim + self.key_dim * num_head * 2

        # Convolution for query, key, and value
        self.qkv_conv = Conv(dim, h, 1, act=False)

        # Projection and Positional encoding convolution
        self.proj_conv = Conv(dim, dim, 1, act=False)
        self.pe_conv = Conv(dim, dim, 3, g=dim, act=False)

    def forward(self, x):
        b, ch, h, w = x.shape

        qkv = self.qkv_conv(x)
        qkv = qkv.view(b, self.num_head, self.key_dim * 2 + self.head_dim,
                       h * w)
        q, k, v = qkv.split([self.key_dim, self.key_dim, self.head_dim], dim=2)
        attn = ((q.transpose(-2, -1) @ k) * self.scale).softmax(dim=-1)
        out = (v @ attn.transpose(-2, -1)).view(b, ch, h, w)

        return self.proj_conv(out + self.pe_conv(v.reshape(b, ch, h, w)))


class PSABlock(nn.Module):
    def __init__(self, inp, num_head=4):
        super().__init__()
        self.att = Attention(inp, num_head)
        self.ffn = nn.Sequential(Conv(inp, inp * 2, 1),
                                 Conv(inp * 2, inp, 1, act=False))

    def forward(self, x):
        x = x + self.att(x)
        return x + self.ffn(x)


class PSA(nn.Module):
    def __init__(self, inp, oup, n=1):
        super().__init__()
        assert inp == oup
        self.conv1 = Conv(inp, 2 * (inp // 2))
        self.conv2 = Conv(2 * (inp // 2), inp)

        self.m = nn.Sequential(
            *(PSABlock(inp // 2, inp // 128) for _ in range(n)))

    def forward(self, x):
        a, b = self.conv1(x).chunk(2, 1)
        return self.conv2(torch.cat((a, self.m(b)), 1))


class DWConv(Conv):
    def __init__(self, inp, oup, k=1, s=1, d=1, act=True):
        super().__init__(inp, oup, k, s, g=math.gcd(inp, oup), d=d, act=act)


class DFL(nn.Module):
    def __init__(self, inp=16):
        super().__init__()
        self.inp = inp
        self.conv = nn.Conv2d(inp, 1, 1, bias=False).requires_grad_(False)
        x = torch.arange(inp, dtype=torch.float).view(1, inp, 1, 1)
        self.conv.weight.data[:] = nn.Parameter(x)

    def forward(self, x):
        b, _, a = x.shape
        out = x.view(b, 4, self.inp, a).transpose(2, 1)
        return self.conv(out.softmax(1)).view(b, 4, a)


class Detect(nn.Module):
    anchors = torch.empty(0)
    strides = torch.empty(0)

    def __init__(self, nc=80, filters=()):
        super().__init__()
        self.nc = nc
        self.reg_max = 16
        self.nl = len(filters)
        self.no = nc + self.reg_max * 4
        self.stride = torch.zeros(self.nl)

        box = max((filters[0] // 4, 64))
        cls = max(filters[0], min(self.nc, 100))

        self.box = nn.ModuleList(
            nn.Sequential(Conv(x, box, 3), Conv(box, box, 3),
                          nn.Conv2d(box, 4 * self.reg_max, 1)) for x in
            filters)

        self.cls = nn.ModuleList(
            nn.Sequential(nn.Sequential(DWConv(x, x, 3), Conv(x, cls, 1)),
                          nn.Sequential(DWConv(cls, cls, 3),
                                        Conv(cls, cls, 1)),
                          nn.Conv2d(cls, self.nc, 1), ) for x in filters)
        self.dfl = DFL(self.reg_max)

    def forward(self, x):
        for i in range(self.nl):
            box_out = self.box[i](x[i])
            cls_out = self.cls[i](x[i])
            x[i] = torch.cat((box_out, cls_out), 1)

        if self.training:
            return x

        bs = x[0].shape
        x_cat = torch.cat([xi.view(bs[0], self.no, -1) for xi in x], 2)
        self.anchors, self.strides = (j.transpose(0, 1) for j in
                                      util.make_anchors(x, self.stride))
        box, cls = x_cat.split((self.reg_max * 4, self.nc), 1)
        lt, rb = self.dfl(box).chunk(2, 1)
        x1y1 = self.anchors.unsqueeze(0) - lt
        x2y2 = self.anchors.unsqueeze(0) + rb
        c_xy, wh = (x1y1 + x2y2) / 2, x2y2 - x1y1
        d_box = torch.cat((c_xy, wh), 1)

        output = torch.cat((d_box * self.strides, cls.sigmoid()), 1)
        return output, x

    def bias_init(self):
        m = self
        for a, b, s in zip(m.box, m.cls, m.stride):
            a[-1].bias.data[:] = 1.0
            b[-1].bias.data[: m.nc] = math.log(5 / m.nc / (640 / s) ** 2)


class Backbone(nn.Module):
    def __init__(self, width, depth, csp):
        super().__init__()

        self.p1 = []
        self.p2 = []
        self.p3 = []
        self.p4 = []
        self.p5 = []

        self.p1.append(Conv(width[0], width[1], 3, 2))

        self.p2.append(Conv(width[1], width[2], 3, 2))
        self.p2.append(CSP(width[2], width[3], depth[0], csp[0], 4))

        self.p3.append(Conv(width[3], width[3], 3, 2))
        self.p3.append(CSP(width[3], width[4], depth[1], csp[0], 4))

        self.p4.append(Conv(width[4], width[4], 3, 2))
        self.p4.append(CSP(width[4], width[4], depth[2], csp[1]))

        self.p5.append(Conv(width[4], width[5], 3, 2))
        self.p5.append(CSP(width[5], width[5], depth[3], csp[1]))
        self.p5.append(SPP(width[5], 5))
        self.p5.append(PSA(width[5], width[5], depth[4]))

        self.p1 = nn.Sequential(*self.p1)
        self.p2 = nn.Sequential(*self.p2)
        self.p3 = nn.Sequential(*self.p3)
        self.p4 = nn.Sequential(*self.p4)
        self.p5 = nn.Sequential(*self.p5)

    def forward(self, x):
        p1 = self.p1(x)
        p2 = self.p2(p1)
        p3 = self.p3(p2)
        p4 = self.p4(p3)
        p5 = self.p5(p4)
        return p3, p4, p5


class Head(nn.Module):
    def __init__(self, width, depth, csp):
        super().__init__()
        self.up = nn.Upsample(scale_factor=2, mode='nearest')
        self.concat = Concat()

        self.h1 = CSP(width[4] + width[5], width[4], depth[0], csp[0])

        self.h2 = CSP(width[4] + width[4], width[3], depth[0], csp[0])

        self.h3 = Conv(width[3], width[3], 3, 2, 1)
        self.h4 = CSP(width[3] + width[4], width[4], depth[0], csp[0])

        self.h5 = Conv(width[4], width[4], 3, 2, 1)
        self.h6 = CSP(width[4] + width[5], width[5], depth[0], csp[1])

        # self.detect = Detect(80, (width[3], width[4], width[5]))

    def forward(self, x):
        p3, p4, p5 = x
        h1 = self.h1(self.concat([self.up(p5), p4]))
        h2 = self.h2(self.concat([self.up(h1), p3]))
        h4 = self.h4(self.concat([self.h3(h2), h1]))
        h6 = self.h6(self.concat([self.h5(h4), p5]))
        return h2, h4, h6


def initialize_weights(model):
    for m in model.modules():
        t = type(m)
        if t is nn.Conv2d:
            pass
        elif t is nn.BatchNorm2d:
            m.eps = 1e-3
            m.momentum = 0.03
        elif t in {nn.Hardswish, nn.LeakyReLU, nn.ReLU, nn.ReLU6, nn.SiLU}:
            m.inplace = True


class YOLO(torch.nn.Module):
    def __init__(self, num_cls, width, depth, csp):
        super().__init__()
        self.backbone = Backbone(width, depth, csp)
        self.head = Head(width, depth, csp)

        img_dummy = torch.zeros(1, width[0], 256, 256)
        self.detect = Detect(num_cls, (width[3], width[4], width[5]))
        self.detect.stride = torch.tensor(
            [256 / x.shape[-2] for x in self.forward(img_dummy)])
        self.stride = self.detect.stride
        self.detect.bias_init()
        initialize_weights(self)


    def forward(self, x):
        x = self.backbone(x)
        x = self.head(x)
        return self.detect(list(x))

    def fuse(self):
        for m in self.modules():
            if type(m) is Conv and hasattr(m, 'norm'):
                m.conv = fuse_conv(m.conv, m.norm)
                m.forward = m.forward_fuse
                delattr(m, 'norm')
        return self


def yolo_v11_n(num_cls=80):
    csp = [False, True]
    depth = [1, 1, 1, 1, 1]
    width = [3, 16, 32, 64, 128, 256]
    return YOLO(num_cls, width, depth, csp)


def yolo_v11_s(num_cls=80):
    csp = [False, True]
    depth = [1, 1, 1, 1, 1]
    width = [3, 32, 64, 128, 256, 512]

    return YOLO(num_cls, width, depth, csp)


def yolo_v11_m(num_cls=80):
    csp = [True, True]
    depth = [1, 1, 1, 1, 1]
    width = [3, 64, 128, 256, 512, 512]

    return YOLO(num_cls, width, depth, csp)


def yolo_v11_l(num_cls=80):
    csp = [True, True]
    depth = [2, 2, 2, 2, 2]
    width = [3, 64, 128, 256, 512, 512]
    return YOLO(num_cls, width, depth, csp)


def yolo_v11_x(num_cls=80):
    csp = [True, True]
    depth = [2, 2, 2, 2, 2]
    width = [3, 96, 192, 384, 768, 768]
    return YOLO(num_cls, width, depth, csp)
